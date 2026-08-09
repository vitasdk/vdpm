#include <stdio.h>

#include <alpm.h>

int main(int argc, char **argv)
{
	alpm_errno_t error;
	alpm_handle_t *handle;

	if(argc != 3) {
		fprintf(stderr, "usage: %s <root> <dbpath>\n", argv[0]);
		return 2;
	}

	handle = alpm_initialize(argv[1], argv[2], &error);
	if(handle == NULL) {
		fprintf(stderr, "alpm_initialize: %s\n", alpm_strerror(error));
		return 1;
	}

	printf("libalpm %s initialized\n", alpm_version());
	if(alpm_release(handle) != 0) {
		fprintf(stderr, "alpm_release failed\n");
		return 1;
	}

	return 0;
}
