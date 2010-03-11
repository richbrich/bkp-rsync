#!/bin/sh

# takes $version as only argument
# checks out tag associated with that version 
# copies the files to the build directory
# updates __VERSION__ and __DATE__
# zips up the stuff


# Configuration
product="bkp-rsync"
release_folder=~/Development/Releases/$product
build_folder=~/Development/Build/$product

echo "rel_folder=$release_folder"

version=$1

if [ "$version" == "" ]; then 
	echo "usage: $0 <version>"
	exit
fi

# must be run from project root
if [ ! -d "./.git" ]; then 
	echo "must be run from project root folder"
	exit
fi

#create directories if they don't exist
if [ ! -d "$release_folder" ]; then
	mkdir -p "$release_folder"
fi

if [ ! -d $build_folder ]; then
	mkdir -p "$build_folder"
fi

# create the destination folder which will contain the actual build
destination_folder="$build_folder/$product-$version"
echo "destination_folder = $destination_folder"
if [ -d $desination_folder ]; then
	echo "deleting existing $destination_folder"
	rm -r "$destination_folder"
fi

mkdir $destination_folder

#checkout the tag we want to build
tag="$product-$version"
git checkout $tag

# copy the files over
cp -R * $destination_folder

#delete the build_scripts folder
echo "removing build scripts"
rm -r "$destination_folder/scripts"

# Replace the version number and date
release_date=`date "+%a %d %h %Y %T"`
echo "release date = $release_date"
echo "version = $version"
cd $destination_folder

version_string="Version: $version"
date_str

sed -i "" 's/__VERSION__/'"$version_string"'/g' bkp-rsync.pl
sed -i "" 's/__DATE__/'"$release_date"'/g' bkp-rsync.pl

# zip up
cd $build_folder
ls
tar cvfz "$product-$version.tgz" "$product-$version"
mv "$product-$version.tgz" $release_folder
rm -r $destination_folder



