/*
 * vdpm-channel: channel manifest helper for the VitaSDK package client.
 *
 * The channel manifest is the only mutable pointer in the distribution, so the
 * client must be able to check it without borrowing interpreters or command
 * line tools from the host. This program provides the three operations the
 * repository refresh needs:
 *
 *   vdpm-channel verify   MANIFEST SIGNATURE PUBLIC_KEY
 *   vdpm-channel validate MANIFEST CHANNEL HOST
 *   vdpm-channel field    MANIFEST CHANNEL HOST FIELD
 *   vdpm-channel describe MANIFEST
 *   vdpm-channel series   INDEX
 *   vdpm-channel deprecated MANIFEST
 *   vdpm-channel sha256   FILE
 *
 * The manifest grammar accepted here is deliberately narrower than JSON. A
 * manifest is canonical when it is the exact serialization produced by sorting
 * object keys and emitting no insignificant whitespace, so this parser accepts
 * only that form directly instead of reparsing and re-serializing to compare.
 * Objects, strings and non-negative integers are the only values the schema
 * uses; arrays, floating point numbers, booleans and null are rejected.
 *
 * String escapes are rejected outright. Every string this schema carries is a
 * repository path, a release tag, an asset name, a hex digest, a host triplet
 * or a channel name, and each is further restricted to a small character set,
 * so no manifest that needs an escape can pass the schema checks anyway.
 * Refusing them removes the escape-decoding logic from a security boundary.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <openssl/evp.h>
#include <openssl/pem.h>

/* A manifest names a handful of releases and digests; anything larger is not
 * something this client should be parsing. */
#define MANIFEST_LIMIT (64u * 1024u)
#define MAX_DEPTH 8
#define ED25519_SIGNATURE_SIZE 64
#define HASH_CHUNK 65536

static const char *program = "vdpm-channel";

static void report(const char *message, const char *detail)
{
	if (detail)
		fprintf(stderr, "%s: %s: %s\n", program, message, detail);
	else
		fprintf(stderr, "%s: %s\n", program, message);
}

/* ------------------------------------------------------------------ nodes */

enum node_type { NODE_OBJECT, NODE_STRING, NODE_INTEGER };

struct member;

struct node {
	enum node_type type;
	char *text;			/* NODE_STRING */
	unsigned long long integer;	/* NODE_INTEGER */
	struct member *members;		/* NODE_OBJECT */
};

struct member {
	char *key;
	struct node *value;
	struct member *next;
};

static void node_free(struct node *value)
{
	struct member *member;

	if (!value)
		return;
	member = value->members;
	while (member) {
		struct member *next = member->next;

		free(member->key);
		node_free(member->value);
		free(member);
		member = next;
	}
	free(value->text);
	free(value);
}

static const struct node *lookup(const struct node *object, const char *key)
{
	const struct member *member;

	if (!object || object->type != NODE_OBJECT)
		return NULL;
	for (member = object->members; member; member = member->next)
		if (strcmp(member->key, key) == 0)
			return member->value;
	return NULL;
}

/* ----------------------------------------------------------------- parser */

struct parser {
	const unsigned char *data;
	size_t size;
	size_t position;
	int depth;
	const char *error;
};

static struct node *parse_value(struct parser *parser);

static struct node *parse_fail(struct parser *parser, const char *message)
{
	if (!parser->error)
		parser->error = message;
	return NULL;
}

static int at_end(const struct parser *parser)
{
	return parser->position >= parser->size;
}

static unsigned char peek(const struct parser *parser)
{
	return at_end(parser) ? 0 : parser->data[parser->position];
}

static int accept(struct parser *parser, unsigned char expected)
{
	if (at_end(parser) || parser->data[parser->position] != expected)
		return 0;
	parser->position++;
	return 1;
}

/*
 * Canonical strings hold printable ASCII only. Space through tilde is exactly
 * the range that needs no escaping, minus the quote and backslash themselves.
 */
static char *parse_string_text(struct parser *parser)
{
	size_t start;
	size_t length;
	char *text;

	if (!accept(parser, '"')) {
		parse_fail(parser, "expected a string");
		return NULL;
	}
	start = parser->position;
	while (!at_end(parser) && parser->data[parser->position] != '"') {
		unsigned char character = parser->data[parser->position];

		if (character == '\\') {
			parse_fail(parser, "string uses an escape sequence");
			return NULL;
		}
		if (character < 0x20 || character > 0x7e) {
			parse_fail(parser, "string uses a non-printable or non-ASCII character");
			return NULL;
		}
		parser->position++;
	}
	if (at_end(parser)) {
		parse_fail(parser, "unterminated string");
		return NULL;
	}
	length = parser->position - start;
	parser->position++;
	text = malloc(length + 1);
	if (!text) {
		parse_fail(parser, "out of memory");
		return NULL;
	}
	memcpy(text, parser->data + start, length);
	text[length] = '\0';
	return text;
}

static struct node *parse_string(struct parser *parser)
{
	char *text = parse_string_text(parser);
	struct node *value;

	if (!text)
		return NULL;
	value = calloc(1, sizeof(*value));
	if (!value) {
		free(text);
		return parse_fail(parser, "out of memory");
	}
	value->type = NODE_STRING;
	value->text = text;
	return value;
}

/*
 * Canonical integers are non-negative and carry no leading zero, sign,
 * fraction or exponent. Rejecting those forms here is what keeps floating
 * point values out of the schema.
 */
static struct node *parse_integer(struct parser *parser)
{
	unsigned long long result = 0;
	struct node *value;
	int digits = 0;

	if (peek(parser) == '0') {
		parser->position++;
		digits = 1;
	} else {
		while (peek(parser) >= '0' && peek(parser) <= '9') {
			unsigned digit = (unsigned)(peek(parser) - '0');

			if (result > (0xffffffffffffffffULL - digit) / 10ULL)
				return parse_fail(parser, "integer is out of range");
			result = result * 10ULL + digit;
			parser->position++;
			digits++;
		}
		if (!digits)
			return parse_fail(parser, "expected a value");
	}
	if (peek(parser) >= '0' && peek(parser) <= '9')
		return parse_fail(parser, "integer has a leading zero");
	if (peek(parser) == '.' || peek(parser) == 'e' || peek(parser) == 'E')
		return parse_fail(parser, "number is not an integer");

	value = calloc(1, sizeof(*value));
	if (!value)
		return parse_fail(parser, "out of memory");
	value->type = NODE_INTEGER;
	value->integer = result;
	return value;
}

static struct node *parse_object(struct parser *parser)
{
	struct node *object = calloc(1, sizeof(*object));
	struct member *last = NULL;

	if (!object)
		return parse_fail(parser, "out of memory");
	object->type = NODE_OBJECT;
	if (!accept(parser, '{')) {
		node_free(object);
		return parse_fail(parser, "expected an object");
	}
	if (accept(parser, '}'))
		return object;

	for (;;) {
		struct member *member;
		char *key = parse_string_text(parser);

		if (!key) {
			node_free(object);
			return NULL;
		}
		/* Canonical output sorts keys, so equal or descending keys mean
		 * the document was not produced canonically. This also rules
		 * out duplicate keys. */
		if (last && strcmp(last->key, key) >= 0) {
			free(key);
			node_free(object);
			return parse_fail(parser, "object keys are not in canonical order");
		}
		member = calloc(1, sizeof(*member));
		if (!member) {
			free(key);
			node_free(object);
			return parse_fail(parser, "out of memory");
		}
		member->key = key;
		if (last)
			last->next = member;
		else
			object->members = member;
		last = member;

		if (!accept(parser, ':')) {
			node_free(object);
			return parse_fail(parser, "expected ':' after an object key");
		}
		member->value = parse_value(parser);
		if (!member->value) {
			node_free(object);
			return NULL;
		}
		if (accept(parser, ','))
			continue;
		if (accept(parser, '}'))
			return object;
		node_free(object);
		return parse_fail(parser, "expected ',' or '}' in an object");
	}
}

static struct node *parse_value(struct parser *parser)
{
	unsigned char character = peek(parser);
	struct node *value;

	if (parser->depth >= MAX_DEPTH)
		return parse_fail(parser, "manifest is nested too deeply");
	parser->depth++;
	if (character == '{')
		value = parse_object(parser);
	else if (character == '"')
		value = parse_string(parser);
	else if (character >= '0' && character <= '9')
		value = parse_integer(parser);
	else
		value = parse_fail(parser, "expected an object, string or integer");
	parser->depth--;
	return value;
}

static struct node *parse_manifest(const unsigned char *data, size_t size, const char **error)
{
	struct parser parser;
	struct node *root;

	memset(&parser, 0, sizeof(parser));
	parser.data = data;
	parser.size = size;

	root = parse_value(&parser);
	if (!root) {
		*error = parser.error ? parser.error : "manifest is not valid";
		return NULL;
	}
	if (root->type != NODE_OBJECT) {
		node_free(root);
		*error = "manifest is not an object";
		return NULL;
	}
	/* Canonical output ends with exactly one newline and nothing else. */
	if (parser.position + 1 != parser.size || parser.data[parser.position] != '\n') {
		node_free(root);
		*error = "manifest has trailing or missing data";
		return NULL;
	}
	return root;
}

/* -------------------------------------------------------------- schema */

static int is_name_character(unsigned char character)
{
	return (character >= 'A' && character <= 'Z') ||
	       (character >= 'a' && character <= 'z') ||
	       (character >= '0' && character <= '9') ||
	       character == '.' || character == '_' || character == '-';
}

/*
 * Names become path components of a release asset URL. The character set has
 * no separator in it, so refusing the two relative directory names is enough
 * to keep a manifest from pointing anywhere but at its own release.
 */
static int is_valid_name(const char *text)
{
	const char *cursor;

	if (!text || !*text)
		return 0;
	for (cursor = text; *cursor; cursor++)
		if (!is_name_character((unsigned char)*cursor))
			return 0;
	return strcmp(text, ".") != 0 && strcmp(text, "..") != 0;
}

static int is_valid_repository(const char *text)
{
	const char *separator;
	char owner[256];
	size_t length;

	if (!text)
		return 0;
	separator = strchr(text, '/');
	if (!separator || strchr(separator + 1, '/'))
		return 0;
	length = (size_t)(separator - text);
	if (length == 0 || length >= sizeof(owner))
		return 0;
	memcpy(owner, text, length);
	owner[length] = '\0';
	return is_valid_name(owner) && is_valid_name(separator + 1);
}

static int is_valid_digest(const char *text)
{
	size_t index;

	if (!text || strlen(text) != 64)
		return 0;
	for (index = 0; index < 64; index++) {
		char character = text[index];

		if (!((character >= '0' && character <= '9') ||
		      (character >= 'a' && character <= 'f')))
			return 0;
	}
	return 1;
}

static const char *string_of(const struct node *object, const char *key)
{
	const struct node *value = lookup(object, key);

	return (value && value->type == NODE_STRING) ? value->text : NULL;
}

static const struct node *check_database(const struct node *owner, const char **error)
{
	const struct node *database = lookup(owner, "database");

	if (!database || database->type != NODE_OBJECT) {
		*error = "manifest is missing a database asset";
		return NULL;
	}
	if (!is_valid_name(string_of(database, "name"))) {
		*error = "manifest has an invalid database asset name";
		return NULL;
	}
	if (!is_valid_digest(string_of(database, "sha256"))) {
		*error = "manifest has an invalid database digest";
		return NULL;
	}
	return database;
}

static int check_section(const struct node *section, const char **error)
{
	if (!section || section->type != NODE_OBJECT) {
		*error = "manifest is missing a required section";
		return 0;
	}
	if (!is_valid_repository(string_of(section, "repository"))) {
		*error = "manifest has an invalid repository identity";
		return 0;
	}
	if (!is_valid_name(string_of(section, "release"))) {
		*error = "manifest has an invalid release tag";
		return 0;
	}
	return 1;
}

/* The world a version 1 manifest is for when it does not say. It is the only
 * world that existed while version 1 was the current schema, so a manifest
 * written then can only have meant this one. Version 2 has to say. */
#define DEFAULT_WORLD "vita"

struct manifest {
	struct node *root;
	const struct node *core;
	const struct node *packages;
	const struct node *core_database;
	const struct node *packages_database;
	const char *world;
};

static int check_manifest(struct manifest *manifest, const char *channel,
			  const char *host, const char **error)
{
	const struct node *root = manifest->root;
	const struct node *schema_version = lookup(root, "schema_version");
	const struct node *sequence = lookup(root, "sequence");
	const struct node *architectures;
	const struct node *host_entry;
	const struct node *world;
	const char *declared;

	if (!schema_version || schema_version->type != NODE_INTEGER ||
	    (schema_version->integer != 1 && schema_version->integer != 2)) {
		*error = "unsupported manifest schema version";
		return 0;
	}
	world = lookup(root, "world");
	if (world) {
		if (world->type != NODE_STRING || world->text[0] == '\0') {
			*error = "manifest names an invalid world";
			return 0;
		}
		manifest->world = world->text;
	} else if (schema_version->integer == 1) {
		manifest->world = DEFAULT_WORLD;
	} else {
		*error = "manifest names no world";
		return 0;
	}
	declared = string_of(root, "channel");
	if (!declared || strcmp(declared, channel) != 0) {
		*error = "manifest declares a different channel";
		return 0;
	}
	if (!sequence || sequence->type != NODE_INTEGER || sequence->integer < 1) {
		*error = "manifest has an invalid channel sequence";
		return 0;
	}

	manifest->core = lookup(root, "core");
	manifest->packages = lookup(root, "packages");
	if (!check_section(manifest->core, error) ||
	    !check_section(manifest->packages, error))
		return 0;

	architectures = lookup(manifest->core, "architectures");
	if (!architectures || architectures->type != NODE_OBJECT) {
		*error = "manifest publishes no host architectures";
		return 0;
	}
	host_entry = lookup(architectures, host);
	if (!host_entry || host_entry->type != NODE_OBJECT) {
		*error = "this host is not published by the channel";
		return 0;
	}
	manifest->core_database = check_database(host_entry, error);
	if (!manifest->core_database)
		return 0;
	manifest->packages_database = check_database(manifest->packages, error);
	if (!manifest->packages_database)
		return 0;
	return 1;
}

/* ------------------------------------------------------------------- io */

static int read_file(const char *path, unsigned char **out, size_t *out_size, size_t limit)
{
	FILE *stream = fopen(path, "rb");
	unsigned char *buffer;
	size_t size = 0;

	if (!stream) {
		report("cannot open file", path);
		return 0;
	}
	buffer = malloc(limit + 1);
	if (!buffer) {
		fclose(stream);
		report("out of memory", NULL);
		return 0;
	}
	size = fread(buffer, 1, limit + 1, stream);
	if (ferror(stream)) {
		fclose(stream);
		free(buffer);
		report("cannot read file", path);
		return 0;
	}
	fclose(stream);
	if (size > limit) {
		free(buffer);
		report("file is larger than the accepted limit", path);
		return 0;
	}
	*out = buffer;
	*out_size = size;
	return 1;
}

static int load_manifest(const char *path, const char *channel, const char *host,
			 struct manifest *manifest)
{
	unsigned char *data;
	size_t size;
	const char *error = NULL;

	if (!read_file(path, &data, &size, MANIFEST_LIMIT))
		return 0;
	memset(manifest, 0, sizeof(*manifest));
	manifest->root = parse_manifest(data, size, &error);
	free(data);
	if (!manifest->root) {
		report(error, path);
		return 0;
	}
	if (!check_manifest(manifest, channel, host, &error)) {
		node_free(manifest->root);
		manifest->root = NULL;
		report(error, path);
		return 0;
	}
	return 1;
}

/* -------------------------------------------------------------- commands */

static int command_verify(const char *manifest_path, const char *signature_path,
			  const char *key_path)
{
	unsigned char *message = NULL;
	unsigned char *signature = NULL;
	size_t message_size = 0;
	size_t signature_size = 0;
	FILE *key_stream;
	EVP_PKEY *key = NULL;
	EVP_MD_CTX *context = NULL;
	int status = 1;

	if (!read_file(manifest_path, &message, &message_size, MANIFEST_LIMIT))
		return 1;
	if (!read_file(signature_path, &signature, &signature_size, ED25519_SIGNATURE_SIZE))
		goto out;
	if (signature_size != ED25519_SIGNATURE_SIZE) {
		report("signature is not an Ed25519 signature", signature_path);
		goto out;
	}

	key_stream = fopen(key_path, "rb");
	if (!key_stream) {
		report("cannot open public key", key_path);
		goto out;
	}
	key = PEM_read_PUBKEY(key_stream, NULL, NULL, NULL);
	fclose(key_stream);
	if (!key) {
		report("cannot read public key", key_path);
		goto out;
	}
	if (EVP_PKEY_base_id(key) != EVP_PKEY_ED25519) {
		report("public key is not an Ed25519 key", key_path);
		goto out;
	}

	context = EVP_MD_CTX_new();
	if (!context) {
		report("out of memory", NULL);
		goto out;
	}
	if (EVP_DigestVerifyInit(context, NULL, NULL, NULL, key) != 1) {
		report("cannot initialize signature verification", NULL);
		goto out;
	}
	/* Ed25519 has no streaming interface; the whole message is verified in
	 * one call. */
	if (EVP_DigestVerify(context, signature, signature_size, message, message_size) != 1) {
		report("signature does not match the manifest", manifest_path);
		goto out;
	}
	status = 0;

out:
	EVP_MD_CTX_free(context);
	EVP_PKEY_free(key);
	free(signature);
	free(message);
	return status;
}

static int print_url(const struct node *section, const struct node *database)
{
	const char *repository = string_of(section, "repository");
	const char *release = string_of(section, "release");
	const char *name = database ? string_of(database, "name") : NULL;
	char url[1024];
	int written;

	if (name)
		written = snprintf(url, sizeof(url),
				   "https://github.com/%s/releases/download/%s/%s",
				   repository, release, name);
	else
		written = snprintf(url, sizeof(url),
				   "https://github.com/%s/releases/download/%s",
				   repository, release);
	if (written < 0 || (size_t)written >= sizeof(url)) {
		report("manifest produces an unreasonably long URL", NULL);
		return 1;
	}
	printf("%s\n", url);
	return 0;
}

static int command_field(const struct manifest *manifest, const char *field)
{
	if (strcmp(field, "sequence") == 0) {
		const struct node *sequence = lookup(manifest->root, "sequence");

		printf("%llu\n", sequence->integer);
		return 0;
	}
	if (strcmp(field, "world") == 0) {
		printf("%s\n", manifest->world);
		return 0;
	}
	if (strcmp(field, "core.database.name") == 0) {
		printf("%s\n", string_of(manifest->core_database, "name"));
		return 0;
	}
	if (strcmp(field, "core.database.sha256") == 0) {
		printf("%s\n", string_of(manifest->core_database, "sha256"));
		return 0;
	}
	if (strcmp(field, "core.database.url") == 0)
		return print_url(manifest->core, manifest->core_database);
	if (strcmp(field, "core.server") == 0)
		return print_url(manifest->core, NULL);
	if (strcmp(field, "packages.database.name") == 0) {
		printf("%s\n", string_of(manifest->packages_database, "name"));
		return 0;
	}
	if (strcmp(field, "packages.database.sha256") == 0) {
		printf("%s\n", string_of(manifest->packages_database, "sha256"));
		return 0;
	}
	if (strcmp(field, "packages.database.url") == 0)
		return print_url(manifest->packages, manifest->packages_database);
	if (strcmp(field, "packages.server") == 0)
		return print_url(manifest->packages, NULL);

	report("unknown field", field);
	return 1;
}

static int command_describe(const char *path)
{
	/* What a stored manifest says, for a client that already trusted it at
	 * refresh time and now only wants to show it. No channel is passed in
	 * because the question is precisely "which one am I on". */
	unsigned char *data;
	size_t size;
	const char *error = NULL;
	struct node *root;
	const struct node *sequence;
	const char *channel;

	if (!read_file(path, &data, &size, MANIFEST_LIMIT))
		return 1;
	root = parse_manifest(data, size, &error);
	free(data);
	if (!root) {
		report(error, path);
		return 1;
	}
	channel = string_of(root, "channel");
	sequence = lookup(root, "sequence");
	if (!channel || !sequence || sequence->type != NODE_INTEGER) {
		report("not a channel manifest", path);
		node_free(root);
		return 1;
	}
	printf("channel\t%s\n", channel);
	printf("sequence\t%llu\n", sequence->integer);
	{
		const struct node *core = lookup(root, "core");
		const struct node *packages = lookup(root, "packages");
		const char *value;

		if (core && (value = string_of(core, "release")))
			printf("core\t%s\n", value);
		if (core && (value = string_of(core, "repository")))
			printf("core_repository\t%s\n", value);
		if (packages && (value = string_of(packages, "release")))
			printf("packages\t%s\n", value);
		if (packages && (value = string_of(packages, "repository")))
			printf("packages_repository\t%s\n", value);
	}
	node_free(root);
	return 0;
}

static int command_deprecated(const char *path)
{
	/* The packages a manifest says nobody should start something new on.
	 * Printed as name and reason so a caller can match without parsing
	 * anything itself. A manifest that carries none is not an error: most
	 * of them do not. */
	unsigned char *data;
	size_t size;
	const char *error = NULL;
	struct node *root;
	const struct node *packages;
	const struct node *deprecated;
	const struct member *member;

	if (!read_file(path, &data, &size, MANIFEST_LIMIT))
		return 1;
	root = parse_manifest(data, size, &error);
	free(data);
	if (!root) {
		report(error, path);
		return 1;
	}
	packages = lookup(root, "packages");
	deprecated = packages ? lookup(packages, "deprecated") : NULL;
	if (deprecated && deprecated->type == NODE_OBJECT)
		for (member = deprecated->members; member; member = member->next)
			if (member->value->type == NODE_STRING)
				printf("%s\t%s\n", member->key, member->value->text);
	node_free(root);
	return 0;
}

static int command_series(const char *path)
{
	/* The release index: which series exist and what state each is in.
	 * Ubuntu publishes the same thing as meta-release, and for the same
	 * reason: without it a release nobody has heard of is undiscoverable,
	 * and one that has ended cannot say so. */
	unsigned char *data;
	size_t size;
	const char *error = NULL;
	struct node *root;
	const struct node *schema_version;
	const struct node *channels;
	const struct member *member;

	if (!read_file(path, &data, &size, MANIFEST_LIMIT))
		return 1;
	root = parse_manifest(data, size, &error);
	free(data);
	if (!root) {
		report(error, path);
		return 1;
	}
	schema_version = lookup(root, "schema_version");
	channels = lookup(root, "channels");
	if (!schema_version || schema_version->type != NODE_INTEGER ||
	    schema_version->integer != 1 || !channels ||
	    channels->type != NODE_OBJECT) {
		report("not a release index", path);
		node_free(root);
		return 1;
	}
	for (member = channels->members; member; member = member->next) {
		const char *status = string_of(member->value, "status");
		const char *summary = string_of(member->value, "summary");

		printf("%s\t%s\t%s\n", member->key, status ? status : "unknown",
		       summary ? summary : "");
	}
	node_free(root);
	return 0;
}

static int command_sha256(const char *path)
{
	FILE *stream = fopen(path, "rb");
	EVP_MD_CTX *context = NULL;
	unsigned char buffer[HASH_CHUNK];
	unsigned char digest[EVP_MAX_MD_SIZE];
	unsigned int digest_size = 0;
	unsigned int index;
	size_t read_size;
	int status = 1;

	if (!stream) {
		report("cannot open file", path);
		return 1;
	}
	context = EVP_MD_CTX_new();
	if (!context || EVP_DigestInit_ex(context, EVP_sha256(), NULL) != 1) {
		report("cannot initialize the digest", NULL);
		goto out;
	}
	while ((read_size = fread(buffer, 1, sizeof(buffer), stream)) > 0)
		if (EVP_DigestUpdate(context, buffer, read_size) != 1) {
			report("cannot hash file", path);
			goto out;
		}
	if (ferror(stream)) {
		report("cannot read file", path);
		goto out;
	}
	if (EVP_DigestFinal_ex(context, digest, &digest_size) != 1) {
		report("cannot finish the digest", NULL);
		goto out;
	}
	for (index = 0; index < digest_size; index++)
		printf("%02x", digest[index]);
	printf("\n");
	status = 0;

out:
	EVP_MD_CTX_free(context);
	fclose(stream);
	return status;
}

static int usage(void)
{
	fprintf(stderr,
		"usage: %s verify   MANIFEST SIGNATURE PUBLIC_KEY\n"
		"       %s validate MANIFEST CHANNEL HOST\n"
		"       %s field    MANIFEST CHANNEL HOST FIELD\n"
		"       %s describe MANIFEST\n"
		"       %s series   INDEX\n"
		"       %s deprecated MANIFEST\n"
		"       %s sha256   FILE\n",
		program, program, program, program, program, program, program);
	return 2;
}

int main(int argc, char **argv)
{
	const char *command;

	if (argc < 2)
		return usage();
	command = argv[1];

	if (strcmp(command, "verify") == 0) {
		if (argc != 5)
			return usage();
		return command_verify(argv[2], argv[3], argv[4]);
	}
	if (strcmp(command, "sha256") == 0) {
		if (argc != 3)
			return usage();
		return command_sha256(argv[2]);
	}
	if (strcmp(command, "describe") == 0) {
		if (argc != 3)
			return usage();
		return command_describe(argv[2]);
	}
	if (strcmp(command, "deprecated") == 0) {
		if (argc != 3)
			return usage();
		return command_deprecated(argv[2]);
	}
	if (strcmp(command, "series") == 0) {
		if (argc != 3)
			return usage();
		return command_series(argv[2]);
	}
	if (strcmp(command, "validate") == 0 || strcmp(command, "field") == 0) {
		int wants_field = strcmp(command, "field") == 0;
		struct manifest manifest;
		int status;

		if (argc != (wants_field ? 6 : 5))
			return usage();
		if (!load_manifest(argv[2], argv[3], argv[4], &manifest))
			return 1;
		status = wants_field ? command_field(&manifest, argv[5]) : 0;
		node_free(manifest.root);
		return status;
	}
	return usage();
}
