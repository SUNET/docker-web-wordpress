#!/bin/bash

#####################################################################
# Name: Updating and distributing content from WordPress REST API   #
# Author: Matias Vangsnes for Sunet                                 #
# Desciption: ...                                                   #
# Dependicies: JQ, Curl, standard UNIX/Linux tools.                 #
#####################################################################

TEMPDIR="/tmp"
REPO="/var/www/html/publish/sunet-www-content"
source=$1
ENVIRONMENT=$2
export HOME="/var/www"

# First, check dependencies
function prog_check {
  if ! which $1 > /dev/null; then
    echo "$1 is NOT installed. Not running."
    return 0
  fi
}

prog_check jq
prog_check curl
prog_check git
prog_check wget

RESULT=$(git config --global user.email)
EXITCODE=$?

if [ ! $EXITCODE -eq 0 ]; then
    git config --global user.email "wordpress@sunet.se"
fi

RESULT=$(git config --global user.name)
EXITCODE=$?

if [ ! $EXITCODE -eq 0 ]; then
    git config --global user.name "Wordpress"
fi


# Check and update the the JSON file with from Wordpress REST API
echo "-- Date: $(date) --"

function update_json {
 COUNT=1

  for i in `seq 1 10`; do

    FILE=$1-$i.json
    curl -ksL "$source/$2?per_page=100&page=$i" | jq '.' > $TEMPDIR/$FILE
    EXITSTATUS=$?

    if [ $EXITSTATUS -ne 0 ]; then
        if [ $i -gt 1 ]; then
            break
        fi
        echo "Error downloading $source/$2, file is not a json object." 1>&2
        exit 1
    fi

    FILESIZE=$(stat --printf="%s" $TEMPDIR/$FILE)

    if [ $FILESIZE -eq 0 ]; then
        if [ $i -gt 1 ]; then
            break
        fi
        echo "Error downloading $source/$2, file size is 0 bytes." 1>&2
        exit 1
    fi

    if [ "x$3" = "xmenu" ]; then
        break
    fi

    EMPTY=$(jq '.[]' $TEMPDIR/$FILE 2>/dev/null)

    if [ "x$EMPTY" = "x" ]; then
        break
    fi

    STATUS=$(jq '.data.status' $TEMPDIR/$FILE 2>/dev/null)

    if [ "x$STATUS" = "x400" ]; then
        break
    fi

    COUNT=$i

  done

  if [ $COUNT -gt 1 ]; then
      for i in `seq 1 $COUNT`; do
          cat $TEMPDIR/$1-$i.json | jq '.[]' > $TEMPDIR/$1-$i-temp.json

      done
      cat $TEMPDIR/$1-[1-$COUNT]-temp.json | jq -s . > $TEMPDIR/$1.json

  else
      cat $TEMPDIR/$1-1.json > $TEMPDIR/$1.json
  fi

  source_json_md5=$(cat $TEMPDIR/$1.json | md5sum | awk '{ print $1 }')
  target_json_md5=$(cat $REPO/$1.json | md5sum | awk '{ print $1 }')

  echo -e "\n-- $1 --"
  if [ "$source_json_md5" = "$target_json_md5" ]; then
    echo "Status: $1 up to date."
    echo "Source (checksum): $source_json_md5"
    echo "Target (checksum): $target_json_md5"
    return 0
  else
    echo "Status: $1 NOT up to date. Updating and commit to GIT."
    echo "Source (checksum): $source_json_md5"
    echo "Target (checksum): $target_json_md5"
    mv $TEMPDIR/$1.json $REPO/$1.json
    git -C $REPO add $1.json
    git -C $REPO commit -m "updated $1"
    return 1
  fi
}

update_json pages wp-json/wp/v2/pages
update_json tjanster wp-json/wp/v2/tjanster
update_json person wp-json/wp/v2/person
update_json evenemang wp-json/wp/v2/evenemang
update_json categories wp-json/wp/v2/categories
update_json header-menu-sv wp-json/menus/v1/menus/header-menu-sv menu
update_json header-menu-en wp-json/menus/v1/menus/header-menu-en menu
update_json header-secondary-menu-sv wp-json/menus/v1/menus/header-secondary-menu-sv menu
update_json header-secondary-menu-en wp-json/menus/v1/menus/header-secondary-menu-en menu

update_json media wp-json/wp/v2/media
EXITSTATUS=$?

if [ $EXITSTATUS -ne 0 ]; then

  for line in $(cat $REPO/media.json | jq -r .[].guid.rendered); do
      cut_y=$(echo "$line" | sed 's/http\(s\)\?:\/\/[^/]\+\///g')

      mkdir -p `dirname "$TEMPDIR/$cut_y"`
      
      #wget -x -nH -nc -q -a $REPO/update-json.log --directory-prefix=$TEMPDIR "$line"
      curl -ksL "$line" > "$TEMPDIR/$cut_y"
      
      FILESIZE=$(stat --printf="%s" "$TEMPDIR/$cut_y")

      if [ $FILESIZE -eq 0 ]; then
	  echo "Error downloading $line, file size is 0 bytes." 1>&2
	  exit 1
      fi
      
      source_json_md5=$(cat "$TEMPDIR/$cut_y" | md5sum | awk '{ print $1 }')
      target_json_md5=$(cat "$REPO/$cut_y" | md5sum | awk '{ print $1 }')
      
      echo -e "\n-- $1 --"
      if [ "$source_json_md5" = "$target_json_md5" ]; then
	  echo "Status: $cut_y up to date."
      else
	  echo "Status: $cut_y NOT up to date. Updating and commit to GIT."

	  mkdir -p `dirname "$REPO/$cut_y"`
	  
	  mv "$TEMPDIR/$cut_y" "$REPO/$cut_y"
	  
	  git -C $REPO add "$cut_y"
	  git -C $REPO commit -m "updated file $cut_y"
	  
      fi
      
  done

  for y in $(find $REPO/wp-content -type f); do
    cut_y=$(echo "$y" | sed "s|${REPO}/||g")

    in_local_json=$(cat $REPO/media.json | jq -r ".[].guid | .rendered" | grep $cut_y | wc -l )
    if [ "$in_local_json" -eq "0" ]; then
	git -C $REPO rm $cut_y
	git -C $REPO commit -m "removed $cut_y" 
    fi
  done
fi

export GIT_SSH_COMMAND='ssh -o UserKnownHostsFile=/var/www/.ssh/known_hosts -i /var/www/.ssh/github'

git -C $REPO push

if [ "$ENVIRONMENT" == "prod" ]; then
    git -C $REPO tag -d prod
    git -C $REPO push origin --delete "prod"
    git -C $REPO tag -m "Prod changed" "prod"
    git -C $REPO push --tags
fi
