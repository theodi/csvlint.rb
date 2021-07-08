#!/bin/bash -e

docker run --rm -ti -u $( id -u ):$( id -g ) -v $PWD:/build -w /build ruby:2.5 \
    bash -e -c '
        echo Installing dependencies
        gem install -g
        echo Building gemfile
        gem build csvlint.gemspec
    '
ls -lF *.gem
