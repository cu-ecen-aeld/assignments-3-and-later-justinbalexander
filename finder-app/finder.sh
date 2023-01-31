#!/bin/sh

print_usage()
{
  msg "Usage: $0 /path/to/dir 'search string'"
}

msg()
{
  echo $@ >&2
}

die()
{
  msg $@
  exit 1
}


main()
{
  if [ "$#" -lt 2 ] || ! [ -d "$1" ]; then
    print_usage
    die
  fi

  num_files=$(find "$1" -type f | wc -l)
  num_matches=$(grep -rF "$2" "$1" | wc -l)
  echo "The number of files are $num_files and the number of matching lines are $num_matches"
}

main $@
