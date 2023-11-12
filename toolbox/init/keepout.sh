#!/bin/bash
#
# keepout [options] < plain_text  > keepout_file
# keepout -d [options] < keepout_file  > plain_text
#
# A wrapper around the 'OpenSSL enc' command to encrypt and decrypt openssl
# encrypted files.  It saves the options that were used as an additional (text)
# header to the encrypted file. This means the exact requirements needed to
# decrypt the file is remembered with the file, even if the default options
# used for file encryption are changed later (it has happened).
#
# More detail...
#
# The "openssl enc" file format does not store the exact metadata needed to
# properly decrypt files it has encrypted.  Meta-data that may change with
# time, so that what was 'default' today, may not be the 'default' tomorrow.
#
# This became especially difficult after openssl v1.1.0 when the password
# hashing 'digest' default changed (from 'md5' to 'sha256'). Also with the
# implementation of PBKDF2 password hashing in v1.1.1 (specifically the number
# of hashing iterations used) the need to save this meta-data became crucial.
#
# Basically the ONLY thing openssl encrypted files saves with the file is some
# file identification 'magic', and a random 'salt' it generated for that
# encryption.  This is not enough information to correct decrypt a openssl
# encrypted file (beyond the password that is).
#
# The "keepout" header saves this information, and is straight forward and
# simple, you can easily add or modify options that have changed in the
# "openssl" command, using a binary savvy editor (like "vim") if needed.  For
# example, you can prepend a header to OLD encryptions, with the appropriate
# (no longer the default) options needed to decrypt those files, turning them
# into a 'keepout' encrypted file (see full documentation below).
#
# Command Options:
#   -d              Decrypt mode
#   --pass method   OpenSSL password method (default will read from TTY)
#   --key KEY       Password Caching Key (store password in a kernel keyring)
#   --clear         Clear KEY from Password Cache, does nothing else
#
#   --help          Summery of options
#   --doc           Full Documentation
#
# Passwords will be asked for (in order for available method) via...
#   * Using method given in "--pass" as per openssl
#   * Via a password helper given in environment variable "$TTY_ASKPASS"
#   * Using "systemd-ask-password" if available
#   * directly from the users TTY, with no echo.
#
###
#
# Usage Example...
#
# Basic encrypt-decrypt pipeline (password is typed in 3 times)
#
#   echo "This is a test message" | keepout | keepout -d
#
# Create an encrypted file, and decrypt it to the terminal
#
#   echo "This is a test message" > test.txt
#   keepout < test.txt > test.kpt  # Encrypt a file (password asked twice)
#   shred -u test.txt              # Securely delete the plain text file
#   cat -v test.kpt; echo          # show the encrypted form of the file
#   keepout -d < test.kpt          # Contents of encrypted file (password)
#
# Edit the above encrypted file - using the password cache.
#
# The password is only entered once, and is re-used to re-encrypt file.  Of
# course this should really be done completely in your text editor (VIM)
# memory, not on disk (see next).
#
#   keepout -d --key "cache_test_pwd" < test.kpt > test.txt
#   vim test.txt
#   keepout --key "cache_test_pwd" < test.txt > test.keepout
#   keepout --key "cache_test_pwd" --clear    # finished, forget password
#   shred -u test.txt test.kpt
#   mv test.keepout test.kpt
#
# Direct editing of encrypted files...
#
# If the encrypted files are saved with a ".kpt" suffix (this is not coded in
# this script), you can use a "vim" editor addition to allow you to edit
# encrypted files directly, in a vim memory buffer, with password caching to
# save the file with the same password again afterwards, all other encryption
# settings will update with whatever the current defaults have been set in
# "keepout" script.
#
#   Vim configuration to edit encrypted (keepout and other) files...
#   https://antofthy.gitlab.io/software/#encrypt.vim
#
#
# Co-Process (call from another program) Usage...
#
# The "--pass" option can be used when calling this command from other
# programs, but with some cavats.  You cannot use "--pass stdin" when
# decrypting the file, due to the need to read the header separately to what is
# passed to the openssl command.  Other methods, such as exampled below, still
# works fine.
#
# Insecure method: using a command line password
#
#   echo "data" | keepout --pass pass:passwd_on_cli > test.kpt
#   keepout -d --pass pass:passwd_on_cli < test.kpt
#
# Secure method: Using a separate file stream, from BASH "here strings"
#
#   echo "data" | keepout --pass fd:4 4<<<"passwd" > test.kpt
#   keepout -d --pass fd:4 4<<<"passwd" < test.kpt
#
# Using file streams like this is a 'secure' method of passing the password to
# either "keepout" or "openssl", such it is not visible in the process table
# and environment.  It is also how this script programmatically calls "openssl".
#
# WARNING: Watch your shell history when doing this from command line!
#
# Secure method: Using a bash fifo filename
#
#   echo "data" | keepout --pass file:<(echo passwd) > test.kpt
#   keepout -d --pass file:<(echo passwd) < test.kpt
#
# The command "echo passwd" can be any command that can output a password.  For
# example, CLI commands to get from the gnome keyring ("secret-tool" or
# "gnome-keyring-cli") or from a password manager (such as "LastPass").
#
#
# File Format...
#
# * 8 byte file magic "KeepOut\n".  Yes it does have a newline in it.
#
# * After this are lines of 'known' openssl options (script validates these).
#
# * A 'data' marker before start of the encrypted data, "__DATA__\n"
#
# * The rest is normally a 'Salted___' encrypted file, from "openssl enc"
# typically in binary, though can be ascii-armored by openssl options.
#
# Example header...
#
#   KeepOut
#   -aes-256-cbc
#   -md sha512
#   -iter 5067274
#   -pbkdf2
#   -salt
#   __DATA__
#
# Encryption defaults used by "keepout" (file magic, cipher, hashing digest,
# and pbkdf2 iteration count) can only be set inside the script, at this time.
# Changing these will not effect the scripts ability to decrypt existing
# 'keepout' files (that is the point after all).  The order of the options does
# not matter.
#
# After the '__DATA__' line (including a newline), is the "openssl enc" output
# generated using those options with the users password.  Note that the
# iteration count is also randomised, as a further 'salting' of the
# encryption.
#
# No openssl arguments (between the 'file magic' and 'data marker') are needed
# in a keepout file (to use "openssl" defaults), though the script will warn
# that certain recommended openssl options are missing.  Using default options
# is not recommended, as these have changed in the past.
#
# If you have an OLD openssl (before v1.1.0) encrypted file you can prepend the
# following header to the file to allow KeepOut to decrypt it.  You will get
# warnings from openssl, but if the options are right it should decrypt the
# appended data.
#
#   KeepOut
#   -aes-256-cbc
#   -md md5
#   -salt
#   __DATA__
#
# For even older 'unsalted' encryptions you can use something like...
#
#   KeepOut
#   -aes-256-cbc
#   -md md5
#   -nosalt
#   __DATA__
#
# A special cipher of -none can also be used to convert unencrypted file into
# a 'keepout' file.  All other encryption settings options are then ignored by
# openssl.  This can be useful in some special circumstances, like reading an
# initial unencrypted file using "keepout", so when it is later saved, using
# "keepout", it will then become encrypted using the keepout's current
# encryption settings (set below).
#
# For example, here is a 'unencrypted' keepout file...
#
#   KeepOut
#   -none
#   ___DATA___
#   unencrypted data file
#
#####
#
# Anthony Thyssen     17 Feburary 2020   Anthony.Thyssen@gmail.com
#
# V1 - 17 February 2020
#   Initial version based on gz2aespipe, but using openssl v1.1.1
#   and its new -pbkdf2 options as a vastly simplified version of
#   my previous encryption script...
#       https://antofthy.gitlab.io/software/#encrypt
#
# V1.1 - 17 Feburary 2020
#   Added ability to use TTY_ASKPASS password helpers, and password caching
#   using the linux kernel keyring
#
# V2 - 2 March 2020
#   Reworked arguments to allow and verify 'known' openssl options to be added
#   to the encrypted file header.  This lets us expand script to add new
#   openssl arguments in the future with backwards compatibility.
#
# V3 - 23 May 2020
#   Added ability to use openssl "-pass" option to allow other programs to
#   use "keepout" for file encryption.  Specifically for my "ks" script.
#
# V4 - 13 September 2020
#   Update to make 'digest tests' a little more backward compatible, to
#   OpenSSL 1.1.1  11 Sep 2018, on Ubuntu 18.04.4 LTS
#   In which "openssl dsgt -list" does not reconise "dgst"
#
# V4.1 - 4 April 2023
#   Bug report from Ivo Doehler < ivodoehler #64; me.com >
#   Read password ourselves if user is supping it via "fd:4"
#   Otherwise we will end up using the wrong password!
#
# V4.2 - 20 June 2023
#   Bug report from  S A < me #64; saudette.net >
#   Backport to use Bash 3 (no Bash 4 tests) for macOS compatibility.
#   With additional check that it is using OpenSSL and not LibreSSL.
#   Allows use of '-a' (alternative for -base64) in keepout header.
#
# V4.3 - 29 June 2023
#   A reorganization of functions, and ensure password variables
#   are not environment variables globally.
#
# Latest version can be downloaded from
#    https://antofthy.gitlab.io/software/#keepout
#
# ----------------------------------------------------------------------------
# Encryption Options....

# OpenSSL name and version needed by this script and the options it uses
openssl_need_name="OpenSSL" # As opposed to the unsupported LibreSSL
openssl_need_vers='1.1.1'

# Encryption Cipher and Digest to use by default
filemagic='KeepOut'   # Must be 7 characters, a newline is added on output.
cipher='aes-256-cbc'  # Cipher to encrypt with, checked below
digest='sha512'       # Digest to hash password, checked below

# Set the Iteration Count '-iter' for '-pbkdf2'...
# The value increases the time it takes to hash the password given,
# and should be large enough to make brute force dictionary attacks difficult.
# It should be large enough to take 1 to 5 seconds to hash the password.
# This value is randomize a little for each encryption, (extra salty).
# The OpenSSL default is '10000' which is VERY VERY small.
#
iteration=5000000    # A much better iteration count than just "10000"
min_iteration=100000 # Decrypt warning if iteration count is less than this!
key_timeout=1800     # How long (secs) to cache password for (for file editing).

# Other "openssl" options for Encrypting (do not set '-iter' here).
# These are not actually required (-salt is default, and -iter enables -pbkdf2)
# but they are recommended to make all the options actually used complete.
#
options=( -salt -pbkdf2 )

# Enable ASCII Armour
# That is save the encryption using base64 encoded ascii, rather than as
# binary.  This may be necessary to allow a keepout file to be mailed.
#
# This also ensures that the vim decrypt-edit-encrypt cycle of "keepout" files
# correctly preserve the final EOL of files.  This is due to the unusual way
# vim deals with that final character.
#
# It is equivelent to the openssl open "-a" which is also acceptable.
#
options+=( -base64 )

# Compress the plain text
# It seemes to do something and result can be decrypted, but in my tests
# encrypted files does not appear to be compressed.  It may require a extra
# compile time options to enable it to work correctly.
#
# See report in: https://stackoverflow.com/questions/62112663/
# Please vote to 'undelete' the post.
#
#options+=( -z )

# ----------------------------------------------------------------------------
# Error Handling...
#
PROGNAME="${BASH_SOURCE##*/}"    # script name (basename)
PROGDIR="${BASH_SOURCE%/*}"      # directory (dirname - may be relative)

Warning() {  # print a program warning
  echo >&2 "$PROGNAME: Warning, $*"
}
EncryptWarn() {  # add a suggestion to warning message
  echo >&2 "$PROGNAME: Warning, $*"
  echo >&2 "     Re-encrypting the file is recommended for better security"
}
Error() {    # Error and exit
  echo >&2 "$PROGNAME: Error: $*"
  exit 2
}
Usage() {  # Report error and Synopsis Usage line only
  echo >&2 "$PROGNAME:" "$@"
  sed >&2 -n '1,2d; /^###/q; /^#/!q; /^#$/q; s/^#  */Usage: /p;' \
          "$PROGDIR/$PROGNAME"
  echo >&2 "For help use  $PROGNAME --help"
  exit 10;
}
Help() {   # Output header comments as documentation
  sed >&2 -n '1d; /^###/q; /^#/!q; s/^#*//; s/^ //; p' \
          "$PROGDIR/$PROGNAME"
  echo >&2 "For full documentation use  $PROGNAME --doc"
  exit 10;
}
Doc() {   # Output the full documentation comments
  sed >&2 -n '1d; /^#####/q; /^#/!q; s/^#*//; s/^ //; p' \
          "$PROGDIR/$PROGNAME"
  exit 10;
}

# ----------------------------------------------------------------------------
# Sanity Checks...

# OpenSSL Name and Version Check
version_test() { printf '%s\n' "$@" | sort -C -V; }
# openssl version looks like "OpenSSL 1.1.1u  30 May 2023"
read -r openssl_curr_name openssl_curr_vers junk <<< $( openssl version )
if [[ "$openssl_curr_name" = "$openssl_need_name" ]]
then :;   # All good - openssl proper
else Error "$openssl_curr_name is not supported by 'keepout' - aborting"
fi
if version_test "$openssl_need_vers" "$openssl_curr_vers"
then :;   # All good - version is new enough
else Error "OpenSSL version is too old for 'keepout' - aborting"
fi
unset version_test openssl_curr_name openssl_curr_vers \
      openssl_need_name openssl_need_vers junk

# Is the Encryption defaults valid!
if openssl list -1 -cipher-commands | grep -q "^$cipher$"
then :;
else Error "Internally set OpenSSL Cipher \"$cipher\" is invalid!"
fi

#if openssl dgst -list |  # "dgst: Unrecognized flag list"
# Option was added 1.1.1e, this test is also used on 'decode', below
if openssl list -1 -digest-commands | grep -q "^$digest$"
then :;
else Error "Internally set OpenSSL Digest \"$digest\" is invalid!"
fi

# FUTURE: Test other defined encryption options?

# ----------------------------------------------------------------------------
# Command line option handling

while [ $# -gt 0 ]; do
  case "$1" in

  -\?|-help|--help) Help ;;              # Basic help
  -doc|--doc)       Doc ;;               # The whole manual

  -d|--decrypt) DECRYPT=true ;;

  -key|--key)     shift; KEY="$1" ;;     # password caching key
  -clear|--clear) CLEAR=true ;;          # clear the key from cache
  -pass|--pass)   shift; PASS="$1" ;;    # openssl password method (no cache)

  --) shift; break ;;                    # forced end of user options
  -*) Usage "Unknown option \"$1\"" ;;
  *)  break ;;                           # unforced  end of user options

  esac
  shift                                  # next option
done
(( $# > 0 )) && Usage "Too Many Arguments"

if [[ -n "$KEY" ]] && [[ -n "$PASS" ]]; then
  Error "Options \"--key\" and \"--pass\" are mutually exclusive"
fi

# ----------------------------------------------------------------------------
#
# Password Reading (with password helper if available)
# See:  https://antofthy.gitlab.io/info/crypto/passwd_input.txt
#

# ensure these are NOT environment variables
unset passwd
unset passwd1

read_noecho() {             # A 'no-echo' TTY Reader (BASH)
  read -r -s -p "$1" passwd </dev/tty >/dev/tty
  echo '' >/dev/tty
}

read_password() {           # Read password from helper, or no-echo fallback
  if [[ "$TTY_ASKPASS" ]]; then
    # User defined password reader
    passwd=$("$TTY_ASKPASS" "$1" </dev/tty )
  elif [ -x /usr/bin/systemd-ask-password ]; then
    # Linux systemd password reader
    passwd=$(/usr/bin/systemd-ask-password "$1" </dev/tty )
  else
    read_noecho "$1"
  fi
  # Final checks -- adjust to suit application
  [[ "$passwd" ]] || Error "Zero length password not allowed."
}

# Read the password twice from user when encrypting
read_password_twice() {
  while true; do
    read_password "Encryption Password :"
    passwd1="$passwd"
    read_password "Encryption Pwd Again:"
    [[ $passwd = $passwd1 ]] && break
    Warning "Password Mismatch -- Try Again!\n"
  done
  unset passwd1    # finished
}

# ----------------------------------------------------------------------------
#
# Clear Password Cache (linux kernel keyring)
#
if [[ $CLEAR ]]; then
  [[ $KEY ]] || Usage "Option --clear requires --key"
  keyctl purge user "$KEY" >/dev/null 2>&1
  exit 0;  # finished
fi

# ---------------------------------------------------------------------------
#
# Decrypt file (with openssl option checking)
#
if [[ $DECRYPT ]]; then

  # Read File Magic
  read -r -n 8 magic
  if [[ $magic != $filemagic ]]; then
    Error "Wrong magic, file is NOT a 'keepout' file - aborting"
    exit 1
  fi

  # Read the openssl options used to encrypt this file...
  options=( )
  while read -r -n 50 option value junk; do
    #echo "DEBUG Header: \"$option\" \"$value\" \"$junk\""
    [[ "$junk" ]] &&  Error "Too many arguments in input file header line"
    case "$option" in
      _DATA_ | __DATA__ | ___DATA___)  # End of options
        break
        ;;
      *[^a-zA-Z0-9-]*)   # only alphanumerics and dashes allowed
        Error "Invalid option (bad char) in input file header"
        ;;
      -none | -z | -a | -base64 |\
      -salt | -nosalt | -pbkdf2)  # valid openssl options without arguments
        [[ $value ]] &&
           Error "Unrequired argument for \"$option\" in input file"
        options+=( "$option" ) # add option to list
        ;;
      -iter)
        case "$value" in
          '' | *[^0-9]*) Error "Invalid iteration count in input file" ;;
        esac
        (( value < min_iteration )) &&
          EncryptWarn "Iteration Count used was very low"
        options+=( "$option" "$value" )
        ;;
      -md)    # password hashing digest to use
        case "$value" in
          *[^a-z0-9-]*)  # value should be lower case, numbers or dashes
             Error "Invalid digest argument used in input file" ;;
          [a-z][a-z0-9-]*) ;;  # it is a posible digest
          *) Error "Invalid digest argument used in input file" ;;
        esac
        if openssl list -1 -digest-commands | grep -q "^$digest$"
        then options+=( "$option" "$value" )
        else Error "Unknown digest argument used in input file"
        fi
        ;;
      -[a-z][a-z]*)
        # This could be the cipher to use (or an invalid option)
        case "$option" in
          *[^a-z0-9-]*)  # option should be lower case, numbers or dashes
            Error "Unknown option in input file header" ;;
        esac
        if openssl list -1 -cipher-commands | grep -q "^${option:1}$"
        then
          [[ $value ]] && Error "Unrequired cypher argument in input file"
          options+=( "$option" )
        else Error "Unknown option or cipher used in input file"
        fi
        ;;
      *)
        Error "Unknown option line in input file"
        ;;
    esac
  done
  # echo "DEBUG Options: ${options[@]}"

  # Warn if specific options were not provided, but let them through.  This may
  # happen if a 'keepout' header is added to an existing encrypted file.
  # It should be cleaned up automatically if and when file is later
  # re-encrypted by "keepout".
  if [[ " ${options[*]} " = *" -none "* ]]; then
    EncryptWarn "File is marked as having no encryption, data is in cleartext"
    PASS='pass:none'  # disable reading a useless password
  else
    if [[ " ${options[*]} " = *" -nosalt "* ]]; then
      EncryptWarn "OpenSSL -nosalt was used when encrypting file"
    fi
    if [[ ! " ${options[*]} " = *" -pbkdf2 "* ]]; then
      EncryptWarn "OpenSSL -pbkdf2 option was not used when encrypting"
    elif [[ ! " ${options[*]} " = *" -iter "* ]]; then
      EncryptWarn "No -iter count given, a very low default value was used"
    fi
  fi

  # Read password from user or cache and update cache
  if [[ ! -n "$PASS" ]]; then
    if [[ -n "$KEY" ]]; then
      if key_id=$(keyctl request user "$KEY" 2>/dev/null); then
        passwd=$(keyctl pipe "$key_id" 3>/dev/null)
      else
        # read passwd and cache it
        read_password "Decryption Password :"
        key_id=$(echo -n "$passwd" | keyctl padd user "$KEY" @u 2>/dev/null)
      fi
      # reset password cache timeout
      keyctl timeout "$key_id" $key_timeout 2>/dev/null
    else
      # read password (no cache)
      read_password "Decryption Password :"
    fi
    PASS="fd:4"  # we will pipe password into openssl
  elif [ "$PASS" == "fd:4" ]; then
    read -r -u 4 passwd   # read password directly if using "fd:4"
  else
    passwd="not_used"     # user suppling password by alternative means
  fi

  # Decrypt the encrypted data using options read from file...
  openssl enc -d "${options[@]}" -in - -out - --pass "$PASS" 4<<<"$passwd"

  exit   # return exit value from "openssl" command
fi

# ----------------------------------------------------------------------------
#
# Encrypt File  (saving openssl options used in a header)
#
if [[ ! -n "$PASS" ]]; then
  if [[ -n "$KEY" ]]; then
    if key_id=$(keyctl request user "$KEY" 2>/dev/null); then
      # get password from password cache
      passwd=$(keyctl pipe "$key_id" 2>/dev/null)
    else
      # read and cache the password
      read_password_twice
      key_id=$(echo -n "$passwd" | keyctl padd user "$KEY" @u 2>/dev/null)
    fi
    # reset password cache timeout (even if it came from cache)
    keyctl timeout "$key_id" $key_timeout 2>/dev/null
  else
    # read the password (no cache)
    read_password_twice
  fi
  PASS="fd:4"  # we will pipe password into openssl
elif [ "$PASS" == "fd:4" ]; then
  read -r -u 4 passwd   # read password directly if using "fd:4"
else
  passwd="not_used"     # user suppling password by alternative means
fi

# Randomise the iteration count to use (extra salty!)
iteration=$(( iteration + RANDOM + RANDOM + RANDOM ))

# Output the keepout header with the openssl options (set above)...
echo "$filemagic"
echo "-$cipher"
echo "-md $digest"
echo "-iter $iteration"
printf '%s\n' "${options[@]}"
echo "__DATA__"   # End of options, start of encrypted file

# Output the encrypted data (with the options set above)...
openssl enc -"$cipher" -md "$digest" -iter "$iteration" "${options[@]}" \
            -in - -out - -pass "$PASS" 4<<<"$passwd"

exit   # return the value from the "openssl" command

-------------------------------------------------------------------------------
