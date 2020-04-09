#!/bin/bash

#####################################################################
# Name: Updating and distributing content from WordPress REST API   #
# Author: Matias Vangsnes for Sunet                                 #
# Desciption: ...                                                   #
# Dependicies: JQ, Curl, standard UNIX/Linux tools.                 #
#####################################################################

REPO="/var/www/html/publish/sunet-www-content"
source="http://web-wp.sunet.se"
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
  source_json_md5=$(curl -sL $source/$2 | md5sum | awk '{ print $1 }')
  target_json_md5=$(cat $REPO/$3 | md5sum | awk '{ print $1 }')
  echo -e "\n-- $1 --"
  if [ "$source_json_md5" = "$target_json_md5" ]; then
    echo "Status: target up to date."
    echo "Source (checksum): $source_json_md5"
    echo "Target (checksum): $target_json_md5"
  else
    echo "Status: target NOT up to date. Updating and commit to GIT."
    echo "Source (checksum): $source_json_md5"
    echo "Target (checksum): $target_json_md5"
    curl -sL $source/$2 > $REPO/$3
    git -C $REPO add $3
    git -C $REPO commit -m "updated $3"
  fi
}

update_json pages wp-json/wp/v2/pages?per_page=100 pages.json
update_json tjanster wp-json/wp/v2/tjanster?per_page=100 tjanster.json
update_json person wp-json/wp/v2/person?per_page=100 person.json
update_json evenemang wp-json/wp/v2/evenemang?per_page=100 evenemang.json
update_json categories wp-json/wp/v2/categories?per_page=100 categories.json
update_json header-menu-sv wp-json/menus/v1/menus/header-menu-sv header-menu-sv.json
update_json header-menu-en wp-json/menus/v1/menus/header-menu-en header-menu-en.json
update_json header-secondary-menu-sv wp-json/menus/v1/menus/header-secondary-menu-sv header-secondary-menu-sv.json
update_json header-secondary-menu-en wp-json/menus/v1/menus/header-secondary-menu-en header-secondary-menu-en.json

# Update the the JSON file with [media] from Wordpress REST API
update_json_media=$(curl -sL $source/wp-json/wp/v2/media | md5sum | awk '{ print $1 }')
current_file_media=$(cat $REPO/media.json?per_page=100 | md5sum | awk '{ print $1 }')

echo -e "\n-- media --"

if [ "$update_json_media" = "$current_file_media" ]; then
  echo "Status: target up to date."
  echo "Source (checksum): $update_json_media"
  echo "Target (checksum):: $current_file_media"
else
  curl -sL $source/wp-json/wp/v2/media?per_page=100 > $REPO/media.json
  echo "Status: target NOT up to date. Updating..."
  echo "Source (checksum): $update_json_media"
  echo "Target (checksum):: $current_file_media"

  git -C $REPO add media.json
  git -C $REPO commit -m "updated media.json"
  
  for line in $(cat $REPO/media.json | jq -r .[].guid.rendered); do
      cut_y=$(echo "$line" | sed "s|${source}/||g")
      
      source_json_md5=$(curl -sL $line | md5sum | awk '{ print $1 }')
      target_json_md5=$(cat $REPO/$cut_y | md5sum | awk '{ print $1 }')
      echo -e "\n-- $1 --"
      if [ "$source_json_md5" = "$target_json_md5" ]; then
	  echo "Status: target up to date."
      else
	  echo "Status: target NOT up to date. Updating and commit to GIT."
	  
	  wget -x -nH -nc -q -a $REPO/update-json.log --directory-prefix=$REPO $line
	  git -C $REPO add $cut_y
	  git -C $REPO commit -m "updated file $cut_y"
	  
      fi
      
  done

  for y in $(find $REPO/wp-content -type f); do
    cut_y=$(echo "$y" | sed "s|${REPO}/||g")
    cut_ya="$source/$cut_y"
    in_local_json=$(cat $REPO/media.json | jq -r ".[].guid | select(.rendered==\"$cut_ya\") .rendered" | cut -d/ -f4- | head -n 1)
    if ! [ "$in_local_json" = "$cut_y" ]; then
	git -C $REPO rm $cut_y
	git -C $REPO commit -m "removed $cut_y" 
    fi
  done
fi

GIT_SSH_COMMAND='ssh -o UserKnownHostsFile=/var/www/.ssh/known_hosts -i /var/www/.ssh/github' git -C $REPO push
