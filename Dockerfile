########################################################################
FROM elixir:1.8.1-slim

ENV SHELL=/bin/sh
ENV application_directory=/usr/src/app
ENV ENABLE_XVBF=true

RUN mkdir -p $application_directory

WORKDIR $application_directory

# Install utilities
RUN apt-get update --fix-missing && apt-get -y upgrade

RUN apt-get update \
    && apt-get install -y gnupg2 g++ wget \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /src/*.deb

# Install latest chrome dev package.
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
    && sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' \
    && apt-get update \
    && apt-get install -y google-chrome-stable --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /src/*.deb

# Add a chrome user and setup home dir.
RUN groupadd --system chrome && \
    useradd --system --create-home --gid chrome --groups audio,video chrome && \
    mkdir --parents /home/chrome/reports && \
    chown --recursive chrome:chrome /home/chrome && \
    chown --recursive chrome:chrome $application_directory

# Run everything after as non-privileged user.
USER chrome

ENV MIX_ENV=prod

# Install Hex + Rebar
RUN mix do local.hex --force, local.rebar --force

# Cache & compile elixir deps
COPY config/ $application_directory/config/
COPY mix.exs mix.lock $application_directory/
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Get rest of application and compile
COPY . $application_directory/
RUN mix compile --no-deps-check

RUN mix do deps.loadpaths --no-deps-check

EXPOSE 4000
ENV PORT=4000

CMD ["mix", "run", "--no-halt"]
