#include <syslog.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>

#define debug(format, ...) \
  syslog(LOG_DEBUG, format, ##__VA_ARGS__)

#define die(format, ...) \
  do { \
    syslog(LOG_ERR, format, ##__VA_ARGS__); \
    exit(EXIT_FAILURE); \
  } while (0)

int main(int argc, const char *argv[argc + 1])
{
  if (argc < 2)
  {
    die("Usage: %s /path/to/file 'string to write'", argv[0]);
  }

  const char *fileName = argv[1];
  const char *stringToWrite = argv[2];

  int maybeFd = open(fileName, O_CREAT|O_TRUNC|O_RDWR, 0666);
  if (maybeFd < 0)
  {
    die("Unable to create file %s", fileName);
  }

  debug("Writing %s to %s", stringToWrite, fileName);
  ssize_t val = write(maybeFd, stringToWrite, strlen(stringToWrite));
  if (val < 0)
  {
    perror("");
  }
  fsync(maybeFd);
  close(maybeFd);

  return 0;
}
