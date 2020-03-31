FROM ruby:2.7.0-buster

RUN apt-get update -y && \
    apt-get install -y ruby ruby-dev libtokyocabinet-dev zlib1g-dev libbz2-dev libxml2-dev libxslt1-dev
RUN gem install bundle

WORKDIR /opt/rbot
COPY Gemfile /opt/rbot/Gemfile
COPY Gemfile.lock /opt/rbot/Gemfile.lock

RUN bundle install

RUN useradd -ms /sbin/nologin rbot && chown rbot /opt/rbot && chown rbot -R /usr/local/bundle
USER rbot

COPY . /opt/rbot

#RUN gem build rbot.gemspec && \
#    gem install rbot-0.9.15.gem

