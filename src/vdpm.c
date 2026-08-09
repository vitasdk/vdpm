/*
 * Native VitaSDK package-manager frontend.
 *
 * vdpm owns the stable user interface and the SDK-local paths. Pacman owns
 * package resolution and transactions. Keeping that boundary at the command
 * line avoids exposing libalpm's ABI and works with the MSYS pacman executable
 * used on Windows.
 */

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <process.h>
#define access _access
#define mkdir_one(path) _mkdir(path)
#else
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#define mkdir_one(path) mkdir((path), 0777)
#endif

enum command {
	COMMAND_INSTALL,
	COMMAND_REMOVE,
	COMMAND_UPGRADE,
	COMMAND_LIST,
	COMMAND_SEARCH,
	COMMAND_INFO,
	COMMAND_FILES,
	COMMAND_PACMAN,
	COMMAND_REFRESH
};

static const char *program_name = "vdpm";

static void usage(FILE *stream)
{
	fputs(
		"VitaSDK package manager\n"
		"\n"
		"Usage:\n"
		"  vdpm install [--force] PACKAGE...\n"
		"  vdpm remove PACKAGE...\n"
		"  vdpm upgrade [PACKAGE...]\n"
		"  vdpm list [PACKAGE...]\n"
		"  vdpm search TERM...\n"
		"  vdpm info PACKAGE...\n"
		"  vdpm files PACKAGE...\n"
		"  vdpm pacman [--] ARG...\n"
		"  vdpm refresh [stable|nightly]\n"
		"\n"
		"Compatibility:\n"
		"  vdpm PACKAGE...       Same as `vdpm install PACKAGE...`\n"
		"  vdpm -f PACKAGE...    Reinstall packages\n"
		"  vdpm -u PACKAGE...    Remove packages\n",
		stream);
}

static int fail(const char *message)
{
	fprintf(stderr, "%s: %s\n", program_name, message);
	return 1;
}

static int fail_path(const char *message, const char *path)
{
	fprintf(stderr, "%s: %s: %s\n", program_name, message, path);
	return 1;
}

static void *allocate(size_t size)
{
	void *value = malloc(size);

	if (!value) {
		fputs("vdpm: out of memory\n", stderr);
		exit(1);
	}
	return value;
}

static char *duplicate_string(const char *text)
{
	size_t size = strlen(text) + 1;
	char *copy = allocate(size);

	memcpy(copy, text, size);
	return copy;
}

static int is_separator(char character)
{
	return character == '/' || character == '\\';
}

static char *normalized_root(const char *input)
{
	char *root;
	size_t index;
	size_t length;

	if (!input || !input[0])
		return NULL;
	root = duplicate_string(input);
	for (index = 0; root[index]; ++index)
		if (root[index] == '\\')
			root[index] = '/';
	length = strlen(root);
	while (length > 1 && root[length - 1] == '/')
		root[--length] = '\0';

#ifdef _WIN32
	{
		int drive_path = length > 3 &&
			((root[0] >= 'A' && root[0] <= 'Z') ||
			 (root[0] >= 'a' && root[0] <= 'z')) &&
			root[1] == ':' && root[2] == '/';
		int unc_path = length > 2 && root[0] == '/' && root[1] == '/';

		if (!drive_path && !unc_path) {
			free(root);
			return NULL;
		}
	}
#else
	if (root[0] != '/' || root[1] == '\0') {
		free(root);
		return NULL;
	}
#endif
	return root;
}

static char *join_path(const char *left, const char *right)
{
	size_t left_length = strlen(left);
	size_t right_length = strlen(right);
	char *result = allocate(left_length + right_length + 2);

	memcpy(result, left, left_length);
	result[left_length] = '/';
	memcpy(result + left_length + 1, right, right_length + 1);
	return result;
}

static int make_directories(const char *path)
{
	char *copy = duplicate_string(path);
	size_t index;
	size_t start = 1;
	int result = 0;

#ifdef _WIN32
	if (copy[1] == ':')
		start = 3;
#endif
	for (index = start; copy[index]; ++index) {
		char saved;

		if (!is_separator(copy[index]))
			continue;
		saved = copy[index];
		copy[index] = '\0';
		if (copy[0] && mkdir_one(copy) != 0 && errno != EEXIST) {
			result = -1;
			copy[index] = saved;
			break;
		}
		copy[index] = saved;
	}
	if (result == 0 && mkdir_one(copy) != 0 && errno != EEXIST)
		result = -1;
	free(copy);
	return result;
}

static int run_process(const char *path, char *const arguments[])
{
	fflush(NULL);
#ifdef _WIN32
	{
		intptr_t status = _spawnv(_P_WAIT, path,
			(const char *const *)arguments);

		if (status == -1) {
			fprintf(stderr, "%s: could not start package client: %s\n",
				program_name, strerror(errno));
			return 1;
		}
		return (int)status;
	}
#else
	execv(path, arguments);
	fprintf(stderr, "%s: could not start package client: %s\n",
		program_name, strerror(errno));
	return 1;
#endif
}

static int command_from_name(const char *name, enum command *command)
{
	if (strcmp(name, "install") == 0)
		*command = COMMAND_INSTALL;
	else if (strcmp(name, "remove") == 0)
		*command = COMMAND_REMOVE;
	else if (strcmp(name, "upgrade") == 0)
		*command = COMMAND_UPGRADE;
	else if (strcmp(name, "list") == 0)
		*command = COMMAND_LIST;
	else if (strcmp(name, "search") == 0)
		*command = COMMAND_SEARCH;
	else if (strcmp(name, "info") == 0)
		*command = COMMAND_INFO;
	else if (strcmp(name, "files") == 0)
		*command = COMMAND_FILES;
	else if (strcmp(name, "pacman") == 0)
		*command = COMMAND_PACMAN;
	else if (strcmp(name, "refresh") == 0)
		*command = COMMAND_REFRESH;
	else
		return 0;
	return 1;
}

static void append_argument(char **arguments, int *count, char *value)
{
	arguments[(*count)++] = value;
}

int main(int argc, char **argv)
{
	const char *root_environment;
	const char *pacman_environment;
	const char *config_environment;
	char *root;
	char *pacman;
	char *configuration;
	char *database;
	char *cache;
	char *log_directory;
	char *log;
	char **arguments;
	int argument_count = 0;
	int input = 1;
	int force = 0;
	int status;
	enum command command = COMMAND_INSTALL;

	if (argc > 1 && (strcmp(argv[1], "-h") == 0 ||
			strcmp(argv[1], "--help") == 0)) {
		usage(stdout);
		return 0;
	}
	if (argc < 2) {
		usage(stderr);
		return 2;
	}

	if (strcmp(argv[input], "-f") == 0) {
		force = 1;
		++input;
	} else if (strcmp(argv[input], "-u") == 0) {
		command = COMMAND_REMOVE;
		++input;
	} else if (command_from_name(argv[input], &command)) {
		++input;
	}

	if (input < argc && strcmp(argv[input], "--force") == 0) {
		if (command != COMMAND_INSTALL)
			return fail("--force is valid only with install");
		force = 1;
		++input;
	}
	if (command == COMMAND_REFRESH)
		return fail("native channel refresh is not implemented yet");

	root_environment = getenv("VITASDK");
	root = normalized_root(root_environment);
	if (!root)
		return fail("VITASDK must be an absolute, non-root path");

	pacman_environment = getenv("VDPM_PACMAN");
	config_environment = getenv("VDPM_PACMAN_CONF");
	if (pacman_environment && pacman_environment[0])
		pacman = duplicate_string(pacman_environment);
#ifdef _WIN32
	else
		pacman = join_path(root, "usr/bin/pacman.exe");
#else
	else
		pacman = join_path(root, "bin/pacman");
#endif
	configuration = config_environment && config_environment[0]
		? duplicate_string(config_environment)
		: join_path(root, "etc/pacman.conf");
	database = join_path(root, "var/lib/pacman");
	cache = join_path(root, "var/cache/pacman/pkg");
	log_directory = join_path(root, "var/log");
	log = join_path(log_directory, "pacman.log");

#ifdef _WIN32
	if (access(pacman, 0) != 0)
#else
	if (access(pacman, X_OK) != 0)
#endif
		return fail_path("package client is not executable", pacman);
	if (access(configuration, 4) != 0)
		return fail_path("package configuration is not readable", configuration);
	if (make_directories(database) != 0 || make_directories(cache) != 0 ||
			make_directories(log_directory) != 0)
		return fail("could not create the package state directories");

	arguments = allocate((size_t)(argc + 24) * sizeof(*arguments));
	append_argument(arguments, &argument_count, pacman);
	append_argument(arguments, &argument_count, "--config");
	append_argument(arguments, &argument_count, configuration);
	append_argument(arguments, &argument_count, "--root");
	append_argument(arguments, &argument_count, root);
	append_argument(arguments, &argument_count, "--dbpath");
	append_argument(arguments, &argument_count, database);
	append_argument(arguments, &argument_count, "--cachedir");
	append_argument(arguments, &argument_count, cache);
	append_argument(arguments, &argument_count, "--logfile");
	append_argument(arguments, &argument_count, log);
	if (command == COMMAND_INSTALL || command == COMMAND_REMOVE ||
			command == COMMAND_UPGRADE)
		append_argument(arguments, &argument_count, "--noscriptlet");
	if (getenv("VDPM_NONINTERACTIVE") &&
			strcmp(getenv("VDPM_NONINTERACTIVE"), "1") == 0) {
		append_argument(arguments, &argument_count, "--noconfirm");
		append_argument(arguments, &argument_count, "--noprogressbar");
	}

	switch (command) {
	case COMMAND_INSTALL:
		if (input >= argc)
			return fail("install requires at least one package");
		append_argument(arguments, &argument_count, "--sync");
		if (!force)
			append_argument(arguments, &argument_count, "--needed");
		break;
	case COMMAND_REMOVE:
		if (input >= argc)
			return fail("remove requires at least one package");
		append_argument(arguments, &argument_count, "--remove");
		break;
	case COMMAND_UPGRADE:
		append_argument(arguments, &argument_count, "--sync");
		if (input >= argc)
			append_argument(arguments, &argument_count, "--sysupgrade");
		break;
	case COMMAND_LIST:
		append_argument(arguments, &argument_count, "--query");
		break;
	case COMMAND_SEARCH:
		if (input >= argc)
			return fail("search requires a term");
		append_argument(arguments, &argument_count, "--sync");
		append_argument(arguments, &argument_count, "--search");
		break;
	case COMMAND_INFO:
		if (input >= argc)
			return fail("info requires at least one package");
		append_argument(arguments, &argument_count, "--sync");
		append_argument(arguments, &argument_count, "--info");
		break;
	case COMMAND_FILES:
		if (input >= argc)
			return fail("files requires at least one package");
		append_argument(arguments, &argument_count, "--query");
		append_argument(arguments, &argument_count, "--list");
		break;
	case COMMAND_PACMAN:
		if (input < argc && strcmp(argv[input], "--") == 0)
			++input;
		if (input >= argc)
			return fail("pacman requires at least one argument");
		break;
	case COMMAND_REFRESH:
		/* Handled before package paths are initialized. */
		break;
	}

	while (input < argc)
		append_argument(arguments, &argument_count, argv[input++]);
	arguments[argument_count] = NULL;
	status = run_process(pacman, arguments);
	free(arguments);
	free(log);
	free(log_directory);
	free(cache);
	free(database);
	free(configuration);
	free(pacman);
	free(root);
	return status;
}
