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
#define popen _popen
#define pclose _pclose
/* There is no /dev/null here, and a redirect to it is itself an error. */
#define DISCARD_ERRORS "2>NUL"
/* Where the Windows bundle actually puts it, next to pacman.exe, rather than
 * in bin/ where the POSIX one lives. */
#define CHANNEL_TOOL "usr/bin/vdpm-channel.exe"
#else
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#define mkdir_one(path) mkdir((path), 0777)
#define DISCARD_ERRORS "2>/dev/null"
#define CHANNEL_TOOL "bin/vdpm-channel"
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
	COMMAND_REFRESH,
	COMMAND_CHANNELS,
	COMMAND_STATUS
};

static const char *program_name = "vdpm";

/* The package that carries the toolchain, and with it this program. */
#define CORE_PACKAGE "vitasdk-core"

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
		"  vdpm refresh [CHANNEL]\n"
		"  vdpm channels\n"
		"  vdpm status\n"
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

/* Every path here is built with forward slashes. That is fine for the calls
 * that execute a program directly -- CreateProcess accepts them, which is why
 * refresh works on Windows -- and wrong for the ones that go through popen:
 * there the line is parsed by cmd, which resolves the program with Windows
 * path rules, where a forward slash begins a switch. cmd answers "the
 * filename, directory name, or volume label syntax is incorrect", which is
 * what `vdpm status` said on Windows instead of working. */
static void to_native_separators(char *path)
{
#ifdef _WIN32
	for (; path && *path; path++)
		if (*path == '/')
			*path = '\\';
#else
	(void)path;
#endif
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

#ifdef _WIN32
/* MSVCRT's spawn family joins argv into a Windows command line but does not
 * protect embedded whitespace for every kind of child executable. Quote using
 * the CommandLineToArgvW rules so native PowerShell and the MSYS CRT receive
 * exactly the argument boundaries vdpm constructed. */
static char *quote_windows_argument(const char *argument)
{
	size_t length = strlen(argument);
	size_t index;
	size_t output = 0;
	int needs_quotes = length == 0;
	char *quoted;

	for (index = 0; index < length; ++index)
		if (argument[index] == ' ' || argument[index] == '\t' ||
			argument[index] == '\n' || argument[index] == '"')
			needs_quotes = 1;
	if (!needs_quotes)
		return duplicate_string(argument);
	quoted = allocate(length * 2 + 3);
	quoted[output++] = '"';
	for (index = 0; index < length;) {
		size_t backslashes = 0;

		while (index < length && argument[index] == '\\') {
			backslashes++;
			index++;
		}
		if (index == length) {
			while (backslashes > 0) {
				quoted[output++] = '\\';
				quoted[output++] = '\\';
				backslashes--;
			}
			break;
		}
		if (argument[index] == '"') {
			while (backslashes > 0) {
				quoted[output++] = '\\';
				quoted[output++] = '\\';
				backslashes--;
			}
			quoted[output++] = '\\';
			quoted[output++] = '"';
		} else {
			while (backslashes > 0) {
				quoted[output++] = '\\';
				backslashes--;
			}
			quoted[output++] = argument[index];
		}
		index++;
	}
	quoted[output++] = '"';
	quoted[output] = '\0';
	return quoted;
}
#endif

static int run_process(const char *path, char *const arguments[])
{
	fflush(NULL);
#ifdef _WIN32
	{
		char **quoted_arguments;
		size_t count = 0;
		size_t index;
		intptr_t status;

		while (arguments[count])
			count++;
		quoted_arguments = allocate((count + 1) * sizeof(*quoted_arguments));
		for (index = 0; index < count; ++index)
			quoted_arguments[index] = quote_windows_argument(arguments[index]);
		quoted_arguments[count] = NULL;
		status = _spawnv(_P_WAIT, path,
			(const char *const *)quoted_arguments);

		for (index = 0; index < count; ++index)
			free(quoted_arguments[index]);
		free(quoted_arguments);

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

#ifdef _WIN32
static int run_windows_script(const char *root, const char *relative,
			      const char *argument)
{
	const char *powershell_environment = getenv("VDPM_POWERSHELL");
	const char *refresh_environment = getenv("VDPM_REFRESH_TOOL");
	const char *system_root = getenv("SystemRoot");
	char *powershell;
	char *refresh;
	char *arguments[10];
	int status;

	if (powershell_environment && powershell_environment[0])
		powershell = duplicate_string(powershell_environment);
	else {
		if (!system_root || !system_root[0])
			return fail("SystemRoot is not set");
		powershell = join_path(system_root,
			"System32/WindowsPowerShell/v1.0/powershell.exe");
	}
	if (refresh_environment && refresh_environment[0])
		refresh = duplicate_string(refresh_environment);
	else
		refresh = join_path(root, relative);
	if (access(powershell, 0) != 0) {
		status = fail_path("Windows PowerShell is not available", powershell);
		free(refresh);
		free(powershell);
		return status;
	}
	if (access(refresh, 4) != 0) {
		status = fail_path("channel helper is not readable", refresh);
		free(refresh);
		free(powershell);
		return status;
	}
	arguments[0] = powershell;
	arguments[1] = "-NoLogo";
	arguments[2] = "-NoProfile";
	arguments[3] = "-NonInteractive";
	arguments[4] = "-ExecutionPolicy";
	arguments[5] = "Bypass";
	arguments[6] = "-File";
	arguments[7] = refresh;
	arguments[8] = (char *)argument;
	arguments[9] = NULL;
	if (!argument)
		arguments[8] = NULL;
	status = run_process(powershell, arguments);
	free(refresh);
	free(powershell);
	return status;
}
#endif

/*
 * Every operation says which release it is acting on.
 *
 * Otherwise the answer to "which VitaSDK is this?" lives in a JSON file
 * nobody opens, and a person can spend an afternoon on a bug that is really
 * "you are on last year's release". It is printed before the work starts, so
 * it is on screen even when the operation fails.
 *
 * Nothing here can stop an operation: if the banner cannot be produced, the
 * command runs anyway.
 */
static void print_release_banner(const char *root)
{
	char *tool = join_path(root, CHANNEL_TOOL);

	to_native_separators(tool);
	char *manifest = join_path(root, "var/lib/vdpm/channel.json");
	char *index = join_path(root, "var/lib/vdpm/index.json");
	char channel[128] = "";
	char sequence[64] = "";
	char command[2048];
	char line[1024];
	FILE *pipe;

	if (!tool || !manifest || !index)
		goto out;
	if (access(manifest, 0) != 0)
		goto out;

	snprintf(command, sizeof(command),
		 "\"%s\" describe \"%s\" " DISCARD_ERRORS,
		 tool, manifest);
	pipe = popen(command, "r");
	if (!pipe)
		goto out;
	while (fgets(line, sizeof(line), pipe)) {
		char *tab = strchr(line, '\t');
		char *newline;

		if (!tab)
			continue;
		*tab = '\0';
		newline = strchr(tab + 1, '\n');
		if (newline)
			*newline = '\0';
		if (strcmp(line, "channel") == 0)
			snprintf(channel, sizeof(channel), "%s", tab + 1);
		else if (strcmp(line, "sequence") == 0)
			snprintf(sequence, sizeof(sequence), "%s", tab + 1);
	}
	pclose(pipe);

	if (!channel[0])
		goto out;
	fprintf(stderr, ":: VitaSDK %s", channel);
	if (sequence[0])
		fprintf(stderr, " (sequence %s)", sequence);
	fputc('\n', stderr);

	/* A release that has ended still installs exactly as it did; what it
	 * must not do is stay silent about it. */
	if (access(index, 0) != 0)
		goto out;
	snprintf(command, sizeof(command),
		 "\"%s\" series \"%s\" " DISCARD_ERRORS,
		 tool, index);
	pipe = popen(command, "r");
	if (!pipe)
		goto out;
	while (fgets(line, sizeof(line), pipe)) {
		char *first = strchr(line, '\t');
		char *second;

		if (!first)
			continue;
		*first = '\0';
		if (strcmp(line, channel) != 0)
			continue;
		second = strchr(first + 1, '\t');
		if (second)
			*second = '\0';
		if (strcmp(first + 1, "end-of-life") == 0)
			fprintf(stderr, ":: %s is no longer maintained; "
				"`vdpm channels` lists what is current\n", channel);
		else if (strcmp(first + 1, "deprecated") == 0)
			fprintf(stderr, ":: %s is deprecated; "
				"`vdpm channels` lists what replaces it\n", channel);
	}
	pclose(pipe);

out:
	free(tool);
	free(manifest);
	free(index);
}

/*
 * Warns about packages that should not be built on any more.
 *
 * Named on the command line, so the warning lands next to the thing being
 * asked for rather than in a list nobody reads. Deprecating is not removing:
 * the install still happens, because everything already depending on it keeps
 * working and taking that decision away helps nobody.
 */
#ifdef _WIN32
/*
 * Refuses an upgrade that would replace the running client, and says how.
 *
 * Windows will not let a running executable be overwritten, and the core
 * package carries both vdpm.exe and pacman.exe — the two programs doing the
 * upgrading. rustup solves the same problem by renaming itself aside, but
 * that only covers the caller: pacman would still be replacing itself
 * mid-transaction. MSYS2 takes the other route and tells you to close
 * everything and run it again, which is what this does, minus the surprise
 * of finding out through a permission error.
 */
static int refuse_self_replacement(char **base, int base_count)
{
	char command[4096];
	char line[512];
	FILE *pipe;
	int offset = 0;
	int index;
	int found = 0;

	for (index = 0; index < base_count && base[index]; index++) {
		/* Only the first element is the program cmd has to resolve. */
		char *native = index == 0 ? duplicate_string(base[index]) : NULL;

		to_native_separators(native);
		offset += snprintf(command + offset, sizeof(command) - offset,
				   "\"%s\" ", native ? native : base[index]);
		free(native);
	}
	snprintf(command + offset, sizeof(command) - offset, "--query --upgrades");

	pipe = popen(command, "r");
	if (!pipe)
		return 0;
	while (fgets(line, sizeof(line), pipe))
		if (strncmp(line, CORE_PACKAGE, strlen(CORE_PACKAGE)) == 0)
			found = 1;
	pclose(pipe);

	if (!found)
		return 0;
	fprintf(stderr,
		"%s: this update replaces the toolchain, which includes vdpm and\n"
		"pacman themselves. Windows cannot overwrite a program while it is\n"
		"running, so run the bootstrap script again instead:\n"
		"\n"
		"  .\\bootstrap-vitasdk.ps1\n"
		"\n"
		"Packages you installed are recorded and reinstalled by it.\n",
		program_name);
	return 1;
}
#endif

static int print_status(const char *root)
{
	/* Native rather than a shell script: this has to answer "which VitaSDK
	 * is this?" on every platform, and Windows has no shell to lean on. */
	char *tool = join_path(root, CHANNEL_TOOL);

	to_native_separators(tool);
	char *manifest = join_path(root, "var/lib/vdpm/channel.json");
	char *index = join_path(root, "var/lib/vdpm/index.json");
	char command[2048];
	char line[1024];
	char channel[128] = "";
	FILE *pipe;
	int status = 1;

	if (!tool || !manifest || !index)
		goto out;
	if (access(manifest, 0) != 0) {
		fprintf(stderr, "%s: no channel configured; run `vdpm refresh` first\n",
			program_name);
		goto out;
	}
	/* Said plainly. Without this the failure arrives as whatever the shell
	 * makes of a program that is not there, which says nothing about what
	 * is missing. */
	if (access(tool, 0) != 0) {
		fprintf(stderr, "%s: this SDK carries no channel tool at %s\n",
			program_name, tool);
		goto out;
	}

	snprintf(command, sizeof(command), "\"%s\" describe \"%s\"", tool, manifest);
	pipe = popen(command, "r");
	if (!pipe)
		goto out;
	while (fgets(line, sizeof(line), pipe)) {
		char *tab = strchr(line, '\t');
		char *newline;

		if (!tab)
			continue;
		*tab = '\0';
		newline = strchr(tab + 1, '\n');
		if (newline)
			*newline = '\0';
		if (strcmp(line, "channel") == 0) {
			snprintf(channel, sizeof(channel), "%s", tab + 1);
			printf("Release   %s\n", tab + 1);
		} else if (strcmp(line, "sequence") == 0)
			printf("Sequence  %s\n", tab + 1);
		else if (strcmp(line, "core") == 0)
			printf("Toolchain %s\n", tab + 1);
		else if (strcmp(line, "packages") == 0)
			printf("Packages  %s\n", tab + 1);
	}
	pclose(pipe);
	status = channel[0] ? 0 : 1;

	if (status == 0 && access(index, 0) == 0) {
		snprintf(command, sizeof(command), "\"%s\" series \"%s\"", tool, index);
		pipe = popen(command, "r");
		if (pipe) {
			while (fgets(line, sizeof(line), pipe)) {
				char *first = strchr(line, '\t');
				char *second;

				if (!first)
					continue;
				*first = '\0';
				if (strcmp(line, channel) != 0)
					continue;
				second = strchr(first + 1, '\t');
				if (second)
					*second = '\0';
				printf("Status    %s\n", first + 1);
			}
			pclose(pipe);
		}
	}

out:
	free(tool);
	free(manifest);
	free(index);
	return status;
}

static void warn_about_deprecated(const char *root, char **argv, int first, int argc)
{
	char *tool = join_path(root, CHANNEL_TOOL);

	to_native_separators(tool);
	char *manifest = join_path(root, "var/lib/vdpm/channel.json");
	char command[2048];
	char line[1024];
	FILE *pipe;
	int index;

	if (!tool || !manifest || first >= argc)
		goto out;
	if (access(manifest, 0) != 0)
		goto out;

	snprintf(command, sizeof(command),
		 "\"%s\" deprecated \"%s\" " DISCARD_ERRORS, tool, manifest);
	pipe = popen(command, "r");
	if (!pipe)
		goto out;
	while (fgets(line, sizeof(line), pipe)) {
		char *tab = strchr(line, '\t');
		char *newline;

		if (!tab)
			continue;
		*tab = '\0';
		newline = strchr(tab + 1, '\n');
		if (newline)
			*newline = '\0';
		for (index = first; index < argc; index++)
			if (strcmp(argv[index], line) == 0)
				fprintf(stderr, ":: %s is deprecated: %s\n",
					line, tab + 1);
	}
	pclose(pipe);

out:
	free(tool);
	free(manifest);
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
	else if (strcmp(name, "channels") == 0)
		*command = COMMAND_CHANNELS;
	else if (strcmp(name, "status") == 0)
		*command = COMMAND_STATUS;
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
	int operands;
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
	root_environment = getenv("VITASDK");
	root = normalized_root(root_environment);
	if (!root)
		return fail("VITASDK must be an absolute, non-root path");
	if (command == COMMAND_STATUS) {
		status = print_status(root);
		free(root);
		return status;
	}
	if (command == COMMAND_CHANNELS) {
		/* This one has to reach the network, which is exactly why refresh
		 * has two implementations. Same split here rather than a shell
		 * script Windows cannot run. */
#ifdef _WIN32
		status = run_windows_script(root, "share/vdpm/list-channels.ps1", NULL);
#else
		{
			char *script = join_path(root, "bin/include/list-channels.sh");
			char *script_arguments[2];

			if (!script) {
				free(root);
				return fail("out of memory");
			}
			script_arguments[0] = script;
			script_arguments[1] = NULL;
			status = run_process(script, script_arguments);
			free(script);
		}
#endif
		free(root);
		return status;
	}
	if (command == COMMAND_REFRESH) {
		if (argc - input > 1) {
			free(root);
			return fail("refresh accepts at most one series");
		}
		/* No default. Refresh is what moves somebody between series, and
		 * the name it used to assume -- stable -- is not a series. */
		if (input >= argc) {
			free(root);
			return fail("refresh requires a series; run `vdpm channels` to see them");
		}
#ifdef _WIN32
		status = run_windows_script(root, "share/vdpm/refresh-repositories.ps1",
			argv[input]);
		free(root);
		return status;
#else
		{
			char *refresh = join_path(root,
				"bin/include/refresh-repositories.sh");
			char *refresh_arguments[3];

			if (access(refresh, X_OK) != 0) {
				status = fail_path("channel refresh helper is not executable",
					refresh);
				free(refresh);
				free(root);
				return status;
			}
			refresh_arguments[0] = refresh;
			refresh_arguments[1] = argv[input];
			refresh_arguments[2] = NULL;
			status = run_process(refresh, refresh_arguments);
			free(refresh);
			free(root);
			return status;
		}
#endif
	}

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
			command == COMMAND_UPGRADE) {
		append_argument(arguments, &argument_count, "--noscriptlet");
		if (getenv("VDPM_NONINTERACTIVE") &&
				strcmp(getenv("VDPM_NONINTERACTIVE"), "1") == 0) {
			append_argument(arguments, &argument_count, "--noconfirm");
			append_argument(arguments, &argument_count, "--noprogressbar");
		}
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
	case COMMAND_CHANNELS:
	case COMMAND_STATUS:
		/* Handled immediately after validating the SDK root. */
		break;
	}

	/* Where the names the user asked for start, before the loop below
	 * consumes them. */
	operands = input;
	while (input < argc)
		append_argument(arguments, &argument_count, argv[input++]);
	arguments[argument_count] = NULL;
	/* Not for the raw passthrough: `vdpm pacman` is the escape hatch and
	 * its output is often piped into something else. */
	if (command != COMMAND_PACMAN) {
		print_release_banner(root);
		if (command == COMMAND_INSTALL)
			warn_about_deprecated(root, argv, operands, argc);
	}
#ifdef _WIN32
	/* Before the transaction rather than after: finding this out through a
	 * permission error leaves a half-applied upgrade behind. */
	if (command == COMMAND_UPGRADE &&
	    refuse_self_replacement(arguments, argument_count)) {
		free(arguments);
		free(log);
		free(log_directory);
		free(cache);
		free(database);
		free(configuration);
		free(pacman);
		free(root);
		return 1;
	}
#endif
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
