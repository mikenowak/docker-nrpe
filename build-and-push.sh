#!/bin/bash

LOGIN=$(git remote get-url origin | sed -r 's/^(https|git)(:\/\/|@)([^\/:]+)[\/:]([^\/:]+)\/(.+).git$/\4/')
REPO=${PWD##*-}

docker build -t ${LOGIN}/${REPO}:latest . &&  docker push ${LOGIN}/${REPO}:latest 
