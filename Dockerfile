FROM ruby:2.5.8-buster

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /usr/src/app

ENV LANG C.UTF-8

COPY ./lib/csvlint/version.rb ./lib/csvlint/
COPY csvlint.gemspec Gemfile Gemfile.lock ./
RUN bundle install

COPY ./ ./

CMD ["./bin/csvlint"]
