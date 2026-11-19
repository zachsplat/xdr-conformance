# php:8.3-cli plus the extensions soneso/stellar-php-sdk requires (gmp, bcmath)
# and composer. Build: docker build -t xdrconf-php:8.3 runners/php
FROM php:8.3-cli
RUN apt-get update && apt-get install -y --no-install-recommends libgmp-dev unzip git \
 && docker-php-ext-install gmp bcmath \
 && rm -rf /var/lib/apt/lists/*
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
