#!/bin/bash

export PS1="\[\e[0;33m\]idea\[\e[0m\]@\[\e[0;32m\]docker\[\e[0m\]:\[\e[0;34m\]\w\[\e[0m\]\$"

MAVEN_VERSION=
# IDEA_RELEASE IS %IDEA_VERSION%@%IDEA_BUILD%
IDEA_RELEASE=
IDEA_BUILD=
IDEA_VERSION=

DOCKER_IMAGE_NAME=
DOCKER_IMAGE_VERSION=
DOCKER_CONTAINER_NAME=

# DOCKER_CONTAINER_USER=
DOCKER_CONTAINER_USER=idea
# DOCKER_CONTAINER_USER=root

PROJECTS_PATH=

DISPLAY_HOST=host.docker.internal
DISPLAY_ID=0
BASE_DOCKER_IMAGE=bellsoft/liberica-openjdk-centos:21.0.2-14

# DOCKER_CONTAINER_START_OPTION=-it
DOCKER_CONTAINER_START_OPTION=-d
# DOCKER_CONTAINER_ADDITIONAL_OPTION=--rm

if [ "$DEFAULT_IDEA_CODE" == "" ]; then
  DEFAULT_IDEA_CODE=IC
fi

# ############################################################ #

if [ "$DOCKER_IMAGE_NAME" == "" ]; then
  DOCKER_IMAGE_NAME=idea
fi
if [ "$DOCKER_IMAGE_VERSION" == "" ]; then
  DOCKER_IMAGE_VERSION=latest
fi

IDEA_CODE="$(awk -vparam1="$1" -viu="IU" -vic="IC" 'BEGIN {
  if ( toupper(param1) == iu ){
    print iu
  } else if ( toupper(param1) == ic ){
    print ic
  }
}')"

if [ "$DOCKER_CONTAINER_NAME" == "" ] && [ "$IDEA_CODE" == "" ]; then
  if [ "$(docker ps -a --filter="ancestor=$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION" --format="table{{.Names}}"|grep -v NAMES|wc -l|xargs)" == "1" ]; then
    DOCKER_CONTAINER_NAME=$(docker ps -a --filter="ancestor=$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION" --format="table{{.Names}}"|grep -v NAMES|xargs)
  elif [ "$(docker ps -a --filter="ancestor=$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION" --filter="name=idea-$DEFAULT_IDEA_CODE" --format="table{{.Names}}"|grep -v NAMES|wc -l|xargs)" == "1" ]; then
    DOCKER_CONTAINER_NAME=$(docker ps -a --filter="ancestor=$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION" --filter="name=idea-$DEFAULT_IDEA_CODE" --format="table{{.Names}}"|grep -v NAMES|xargs)
  fi
  if [ ! "$DOCKER_CONTAINER_NAME" == "" ]; then
    echo Found docker container: $DOCKER_CONTAINER_NAME
    if [ ! "$(docker ps|grep -E "^.*$DOCKER_IMAGE_NAME\:$DOCKER_IMAGE_VERSION\s+.*$DOCKER_CONTAINER_NAME\s*"|wc -l|xargs)" == 0 ]; then
      echo IDEA Container is already started
      exit -1;
    fi;
  fi;
fi

if [ "$IDEA_CODE" == "" ]; then
  IDEA_CODE=$DEFAULT_IDEA_CODE
fi;
IDEA_ID="$(awk -vid="$IDEA_CODE" 'BEGIN { print tolower(id) }')"


if [ "$DOCKER_CONTAINER_NAME" == "" ]; then
  DOCKER_CONTAINER_NAME=idea-$IDEA_CODE
fi


if [ ! "$(docker ps --filter="ancestor=$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION" --format="table{{.Names}}"|grep -v NAMES|wc -l|xargs)" == "0" ]; then
  echo IDEA Container is already started: "$(docker ps --filter="ancestor=$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION" --format="table{{.Names}}"|grep -v NAMES|xargs)"
  exit -1;  
fi

if [ ! "$(docker ps -a|grep -E "^.*$DOCKER_IMAGE_NAME\:$DOCKER_IMAGE_VERSION\s+.*$DOCKER_CONTAINER_NAME\s*"|wc -l|xargs)" == "0" ]; then
  echo Start existed container: $DOCKER_CONTAINER_NAME
  xhost + > /dev/null
  docker start "$DOCKER_CONTAINER_NAME"

else
  
  # Identify Maven Version
  if [ "$MAVEN_VERSION" == "" ]; then
    MAVEN_VERSION="$(curl https://archive.apache.org/dist/maven/maven-3/ 2>/dev/null|grep -E 'href=\"\d+\.\d+\.\d+\/\"'|sed -nE 's/^.*href="(.*)\/".*$/\1/p'|sort -r|head -n1)"
  fi
  MAVEN_NAME=apache-maven-$MAVEN_VERSION
  MAVEN_FILE_NAME=apache-maven-"$MAVEN_VERSION"-bin.tar.gz
  echo Maven version: $MAVEN_VERSION, name: $MAVEN_NAME, file: $MAVEN_FILE_NAME
  
  if [ ! -d "docs" ]; then
    mkdir -p docs
  fi
  
  # Load java api-doc
  if [ ! -f "docs/jdk-21.0.2_doc-all.zip" ]; then
    wget https://download.oracle.com/otn_software/java/jdk/21.0.2+13/f2283984656d49d69e91c558476027ac/jdk-21.0.2_doc-all.zip -O docs/jdk-21.0.2_doc-all.zip
  fi
  
  # Identify IDEA Version
  if [ "$IDEA_BUILD" == "" ] || [ "$IDEA_VERSION" == "" ]; then
    if [ "$IDEA_RELEASE" == "" ]; then
      IDEA_RELEASE="$(curl https://www.jetbrains.com/updates/updates.xml 2> /dev/null| grep "IntelliJ IDEA RELEASE" -A 3|grep "build number"|sed -nE 's/^.*version="(.*)" release.*fullNumber="(.*)".*$/\1@\2/p')"
    fi
    if [ "$IDEA_BUILD" == "" ]; then
      IDEA_BUILD="$(echo $IDEA_RELEASE|sed -nE 's/^.*@(.*)$/\1/p')"
    fi
    if [ "$IDEA_VERSION" == "" ]; then
      IDEA_VERSION="$(echo $IDEA_RELEASE|sed -nE 's/^(.*)@.*$/\1/p')"
    fi
  fi
  IDEA_NAME=idea-"$IDEA_CODE"-"$IDEA_BUILD"
  IDEA_FILE_NAME=idea"$IDEA_CODE"-"$IDEA_VERSION".tar.gz
  echo IDEA version: $IDEA_VERSION, name: $IDEA_NAME, file: $IDEA_FILE_NAME
    
  
  if [ ! -d "$MAVEN_NAME" ]; then
    if [ ! -f "$MAVEN_FILE_NAME" ]; then
      echo Download Maven distributive: $MAVEN_FILE_NAME
      wget "https://www.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/$MAVEN_FILE_NAME"
    else
      echo Maven distributive already exists: $MAVEN_FILE_NAME
    fi
    echo Extract Maven files to: $MAVEN_NAME from: $MAVEN_FILE_NAME
    tar -xzf "$MAVEN_FILE_NAME"
  else
    echo Maven home already exists: $MAVEN_NAME
  fi
  
  if [ ! -d "$IDEA_NAME" ]; then
    if [ ! -f "$IDEA_FILE_NAME" ]; then
      echo Download IDEA distributive: $IDEA_FILE_NAME
      wget https://download.jetbrains.com/idea/"$IDEA_FILE_NAME"
    else
      echo IDEA distributive already exists: $IDEA_FILE_NAME
    fi
    echo Extract IDEA files to: $IDEA_NAME from: $IDEA_FILE_NAME
    tar -xzf "$IDEA_FILE_NAME"
  else
    echo IDEA home already exists: $IDEA_NAME
  fi
  
  if [ "$DOCKER_CONTAINER_USER" == "" ]; then
    DOCKER_CONTAINER_USER=$USER
  fi
  if [ "$DOCKER_CONTAINER_USER" == "root" ]; then
    DOCKER_CONTAINER_USER_HOME='/root'
  else
    DOCKER_CONTAINER_USER_HOME="/home/$DOCKER_CONTAINER_USER"        
  fi

  USRID=$(id -u $USER)
  GROUPID=$(id -g $USER)
      
  if [ "$(docker images|grep "^$DOCKER_IMAGE_NAME\s*$DOCKER_IMAGE_VERSION\s.*$"|wc -l|xargs)" == "0" ]; then
    
    if [ ! -f "Dockerfile" ]; then

      echo FROM $BASE_DOCKER_IMAGE > Dockerfile
      echo USER root >> Dockerfile
      echo 'RUN yum -y install lksctp-tools xorg-x11-server-Xorg xorg-x11-xauth xorg-x11-apps libXtst sudo whoami \' >> Dockerfile
      echo ' && yum clean all \' >> Dockerfile
      echo ' && usermod -p "" root \' >> Dockerfile
      if [ ! "$DOCKER_CONTAINER_USER" == "root" ]; then
        echo " && groupadd -g $GROUPID -f staff \\" >> Dockerfile
        echo " && useradd -m -d $DOCKER_CONTAINER_USER_HOME -u $USRID -g $GROUPID $DOCKER_CONTAINER_USER \\" >> Dockerfile
        echo ' && usermod -aG wheel -p "" '$DOCKER_CONTAINER_USER' \' >> Dockerfile
      fi
      echo ' && ln -s /opt/maven/bin/mvn /usr/bin/mvn \' >> Dockerfile
      echo ' && ln -s /opt/idea/bin/idea.sh /usr/bin/idea' >> Dockerfile
      echo USER $DOCKER_CONTAINER_USER >> Dockerfile
      echo "ENV M2_HOME $DOCKER_CONTAINER_USER_HOME/.m2" >> Dockerfile
      echo ENV MAVEN_HOME /opt/apache-maven >> Dockerfile
      echo ENV MAVEN_OPTS=-Xms128m >> Dockerfile
      echo ENV LOCALE=en_RU.UTF-8 >> Dockerfile
      echo ENV DISPLAY=$DISPLAY_HOST:$DISPLAY_ID >> Dockerfile
      echo "ENV MAVEN_CONFIG=\"-s $DOCKER_CONTAINER_USER_HOME/.m2/settings.xml\"" >> Dockerfile
      echo EXPOSE 80 8080 5005 >> Dockerfile
      echo "WORKDIR $DOCKER_CONTAINER_USER_HOME" >> Dockerfile
      echo ENTRYPOINT idea >> Dockerfile
      echo Dockerfile has been created
    else
      echo Dockerfile already exists
    fi
    echo Create Docker image $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION
    docker build -t $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION . --no-cache
  else
    echo Docker image "$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION" is already exists
  fi
  
  if [ "$PROJECTS_PATH" == "" ]; then
    PROJECTS_PATH=./IdeaProjects
  fi
  
  echo IdeaProject path: $PROJECTS_PATH
  
  if [ ! -d "$PROJECTS_PATH" ]; then
    mkdir -p "$PROJECTS_PATH"
  fi
  
  xhost + > /dev/null

  if [ ! "$DOCKER_CONTAINER_USER" == "root" ]; then
    USERPARAM=--user \"$USRID:$GROUPID\"
  fi
  echo Run docker container: $DOCKER_CONTAINER_NAME
  docker run $DOCKER_CONTAINER_START_OPTION $DOCKER_CONTAINER_ADDITIONAL_OPTION \
    --name $DOCKER_CONTAINER_NAME \
    --mount type=bind,source=/tmp/.X11-unix,target=/tmp/.X11-unix \
    --mount type=bind,source=$HOME/.m2,target=$DOCKER_CONTAINER_USER_HOME/.m2 \
    --mount type=bind,source=./$IDEA_NAME,target=/opt/idea \
    --mount type=bind,source=./$MAVEN_NAME,target=/opt/maven \
    --mount type=bind,source="$PROJECTS_PATH",target=$DOCKER_CONTAINER_USER_HOME/IdeaProjects \
    --mount type=bind,source=./docs,target=$DOCKER_CONTAINER_USER_HOME/docs \
    $USERPARAM "$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION"
fi
