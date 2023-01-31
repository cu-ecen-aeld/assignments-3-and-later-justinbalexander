#!/bin/sh

print_usage()
{
  msg "Usage: $0 /path/to/file 'string to write'"
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
  if [ "$#" -lt 2 ]; then
    print_usage
    die
  fi

  mkdir -p "$(dirname "$1")"
  echo "$2" > "$1"

  if ! [ -f "$1" ]; then
    die "Unable to create file $1"
  fi
}

main $@
