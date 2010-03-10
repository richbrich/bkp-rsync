#!/bin/sh

product="bkp-rsync"

version=$1
if [ "$version" == "" ]; then
	echo "usage: $0 <version>"
	exit
fi

git checkout master

status=`git status --porcelain`
if [ "$status" != "" ];  then
	echo "** Tree not ready. stopping"
	exit
fi

# Tag
tag="$product-$version"
git tag -m "Release tag for version $version" -a $tag
git push origin master
git push --tags



