#! /usr/bin/env bash

## You need git + phpcs + coder 8.x-2.x + eslint + codespell

if [[ $# -lt 1 || $1 == "--help" || $1 == "-h" ]]
then
  echo "Usage:    `basename $0` DIR-PATH"
  echo "Examples:"
  echo "  `basename $0` sites/all/modules/rules"
  exit
fi

# Get the directory pareview.sh is stored in to access config files such as
# eslint.json later.
SOURCE="${BASH_SOURCE[0]}"
# resolve $SOURCE until the file is no longer a symlink
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
PAREVIEWSH_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"


# check if the first argument is valid directory.
if [ -d $1 ]; then
 cd $1
else
  echo "Directory does not exist"
  exit 1
fi

# Get module/theme name.
# If there is more than one info file we take the one with the shortest file
# name. We look for *.info (Drupal 7) and *.info.yml (Drupal 8) files.
INFO_FILE=`ls | grep '\.info\(\.yml\)\?$' | awk '{ print length($0),$0 | "sort -n"}' | head -n1 | grep -o -E "[^[:space:]]*$"`
NAME=${INFO_FILE%%.*}
PHP_FILES=`find . -name \*.module -or -name \*.php -or -name \*.inc -or -name \*.install -or -name \*.test -or -name \*.profile`
NON_TPL_FILES=`find . -not \( -name \*.tpl.php \) -and \( -name \*.module -or -name \*.php -or -name \*.inc -or -name \*.install -or -name \*.test -name \*.profile \)`
CODE_FILES=`find . -name \*.module -or -name \*.php -or -name \*.inc -or -name \*.install -or -name \*.js -or -name \*.test`
TEXT_FILES=`find . -name \*.module -or -name \*.php -or -name \*.inc -or -name \*.install -or -name \*.js -or -name \*.test -or -name \*.css -or -name \*.txt -or -name \*.info -or -name \*.yml`
FILES=`find . -path ./.git -prune -o -type f -print`
INFO_FILES=`find . -name \*.info`
# ensure $PHP_FILES is not empty
if [ -z "$PHP_FILES" ]; then
  # just set it to the current directory.
  PHP_FILES="."
  CODE_FILES="."
  NON_TPL_FILES="."
fi

# README.txt present?
function check_readme {
  if [ ! -e README.txt ] && [ ! -e README.md ] ; then
    echo "README.md or README.txt is missing, see the guidelines for in-project documentation."
    exit 1;
  fi

  # There should be only one README file either *.md or *.txt, not both.
  if [ -e README.txt ] && [ -e README.md ] ; then
    echo "There should be only one README file, either README.md or README.txt."
    exit 1;
  fi
}

# LICENSE.txt present?
function check_license {
  if [ -e LICENSE.txt ]; then
    echo "Remove LICENSE.txt, it will be added by drupal.org packaging automatically."
    exit 1;
  fi

  if [ -e LICENSE ]; then
    echo "Remove the LICENSE, drupal.org packaging will add a LICENSE.txt file automatically."
    exit 1;
  fi
}

# translations folder present?
function check_translations {
  if [ -d translations ]; then
    echo "Remove the translations folder, translations are done on http://localize.drupal.org"
    exit 1;
  fi
}

# .DS_Store present?
function check_os_files {
  CHECK_FILES=".DS_Store .idea node_modules .project .sass-cache .settings vendor"
  for FILE in $CHECK_FILES; do
    FOUND=`find . -name $FILE`
    if [ -n "$FOUND" ]; then
      echo "Remove all $FILE files from your repository."
      exit 1;
    fi
  done
}

# Backup files present?
function check_backup_files {
  BACKUP=`find . -name "*~"`
  if [ ! -z "$BACKUP" ]; then
    echo "Remove all backup files from your repository:"
    echo "$BACKUP"
    exit 1;
  fi
}

function check_info_files {
  for FILE in $INFO_FILES; do
    # "version" in info file?
    grep -q -e "version[[:space:]]*=[[:space:]]*" $FILE
    if [ $? = 0 ]; then
      echo "Remove \"version\" from the $FILE file, it will be added by drupal.org packaging automatically."
      exit 1;
    fi

    # "project" in info file?
    grep -q -e "project[[:space:]]*=[[:space:]]*" $FILE
    if [ $? = 0 ]; then
      echo "Remove \"project\" from the $FILE file, it will be added by drupal.org packaging automatically."
      exit 1;
    fi

    # "datestamp" in info file?
    grep -q -e "datestamp[[:space:]]*=[[:space:]]*" $FILE
    if [ $? = 0 ]; then
      echo "Remove \"datestamp\" from the $FILE file, it will be added by drupal.org packaging automatically."
      exit 1;
    fi
  done
}

# ?> PHP delimiter at the end of any file?
function check_php_tags {
  BAD_LINES=`grep -l "^\?>" $NON_TPL_FILES 2> /dev/null`
  if [ $? = 0 ]; then
    echo "The \"?>\" PHP delimiter at the end of files is discouraged, see https://www.drupal.org/node/318#phptags"
    echo "$BAD_LINES"
    exit 1;
  fi
}

# Functions without module prefix.
function check_module_functions {
  # Exclude *.api.php and *.drush.inc files.
  CHECK_FILES=`echo "$PHP_FILES" | grep -v -E "(api\.php|drush\.inc)$"`
  ERROR_COUNT=0
  for FILE in $CHECK_FILES; do
    FUNCTIONS=`grep -E "^function [[:alnum:]_]+.*\(.*\) \{" $FILE 2> /dev/null | grep -v -E "^function (_?$NAME|theme|template|phptemplate)"`
    if [ $? = 0 ]; then
      echo "$FILE: all functions should be prefixed with your module/theme name to avoid name clashes. See https://www.drupal.org/node/318#naming"
      echo "$FUNCTIONS"
      ERROR_COUNT=1
    fi
  done
  if [ $ERRORS_COUNT -ne 0 ]; then
    exit 1;
  fi
}

# bad line endings in files
function check_lineendings {
  BAD_LINES1=`file $FILES | grep "line terminators"`
  # the "file" command does not detect bad line endings in HTML style files, so
  # we run this grep command in addition.
  BAD_LINES2=`grep -rlI $'\r' *`
  if [ -n "$BAD_LINES1" ] || [ -n "$BAD_LINES2" ]; then
    echo "Bad line endings were found, always use unix style terminators. See https://www.drupal.org/coding-standards#indenting"
    echo "$BAD_LINES1"
    echo "$BAD_LINES2"
    exit 1;
  fi
}

# old CVS $Id$ tags
function check_old_cvs {
  BAD_LINES=`grep -rnI "\\$Id" *`
  if [ $? = 0 ]; then
    echo "Remove all old CVS \$Id tags, they are not needed anymore."
    echo "$BAD_LINES"
    exit 1;
  fi
}

# PHP parse error check
function check_php_parse {
  ERRORS_COUNT=0
  for FILE in $PHP_FILES; do
    ERRORS=`php -l $FILE 2>&1`
    if [ $? -ne 0 ]; then
      echo "$ERRORS"
      ERRORS_COUNT=1
    fi
  done

  if [ $ERRORS_COUNT -ne 0 ]; then
    exit 1;
  fi
}

# \feff character check at the beginning of files.
function check_file_start {
  ERRORS_COUNT=0
  for FILE in $TEXT_FILES; do
    ERRORS=`grep ^$'\xEF\xBB\xBF' $FILE`
    if [ $? = 0 ]; then
      echo "$FILE: the byte order mark at the beginning of UTF-8 files is discouraged, you should remove it."
      ERRORS_COUNT=1
    fi
  done
  if [ $ERRORS_COUNT -ne 0 ]; then
    exit 1;
  fi
}

# Run drupalcs.
function check_drupalcs {
  # If the project contains SCSS files then we don't check the included CSS files
  # because they are probably generated.
  SCSS_FILES=`find . -path ./.git -prune -o -type f -name \*.scss -print`
  if [ -z "$SCSS_FILES" ]; then
    DRUPALCS=`phpcs --standard=Drupal --report-width=74 --extensions=php,module,inc,install,test,profile,theme,css,info,txt,md,yml . 2>&1`
  else
    DRUPALCS=`phpcs --standard=Drupal --report-width=74 --extensions=php,module,inc,install,test,profile,theme,info,txt,md,yml . 2>&1`
  fi
  DRUPALCS_ERRORS=$?
  if [ $DRUPALCS_ERRORS -gt 0 ]; then
    LINES=`echo "$DRUPALCS" | wc -l`
    echo "Coder Sniffer has found some issues with your code (please check the Drupal coding standards)."
    echo "$DRUPALCS"
    if [ $LINES -gt 20 ]; then
      exit 1;
    fi
  fi
}

# Check if eslint is installed.
function check_eslint {
  hash eslint 2>/dev/null
  if [ $? = 0 ]; then
    # Run eslint.
    ESLINT=`eslint --config $PAREVIEWSH_DIR/eslint.json --format compact . 2>&1`
    ESLINT_ERRORS=$?
    if [ $ESLINT_ERRORS -gt 0 ]; then
      LINES=`echo "$ESLINT" | wc -l`
      echo "ESLint has found some issues with your code (please check the JavaScript coding standards)."
      echo "$ESLINT"
      if [ $LINES -gt 20 ]; then
        exit 1;
      fi
    fi
  fi
}

# Run DrupalPractice
function check_drupal_practice {
  DRUPALPRACTICE=`phpcs --standard=DrupalPractice --report-width=74 --extensions=php,module,inc,install,test,profile,theme,yml . 2>&1`
  if [ "$?" -gt 0 ]; then
    echo "DrupalPractice has found some issues with your code, but could be false positives."
    echo "$DRUPALPRACTICE"
    exit 1;
  fi
}

# Run DrupalSecure and ignore stderr because it sometimes throws PHP warnings.
function check_drupal_secure {
  DRUPALSECURE=`phpcs --standard=DrupalSecure --report-width=74 --extensions=php,module,inc,install,test,profile,theme . 2> /dev/null`
  if [ $? = 1 ]; then
    echo "DrupalSecure has found some issues with your code (please check the Writing secure core handbook)."
    echo "$DRUPALSECURE"
    exit 1;
  fi
}

# Check if codespell is installed.
function check_codespell {
  hash codespell 2>/dev/null
  if [ $? = 0 ]; then
    # Run codespell.
    SPELLING=`codespell -d . 2>/dev/null`
    if [ ! -z "$SPELLING" ]; then
      echo "Codespell has found some spelling errors in your code."
      echo "$SPELLING"
      exit 1;
    fi
  fi
}

# Check if the project contains automated tests.
function check_tests {
  D7_TEST_FILES=`find . -name \*\.test`
  D8_TEST_DIRS=`find . -type d \( -iname test -or -iname tests \)`
  # Do not throw this error for themes, they usually don't have tests.
  if [ -z "$D7_TEST_FILES" ] && [ -z "$D8_TEST_DIRS" ] && [ ! -e template.php ] && [ ! -e *.theme ] ; then
    echo "No automated test cases were found, did you consider writing Simpletests or PHPUnit tests? This is not a requirement but encouraged for professional software development."
  fi
}

check_readme
check_license
check_translations
check_os_files
check_backup_files
check_info_files
check_php_tags
check_module_functions
check_lineendings
check_old_cvs
check_php_parse
check_file_start
check_drupalcs
check_eslint
check_drupal_practice
check_drupal_secure
check_codespell
check_tests
