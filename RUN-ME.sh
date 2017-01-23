#!/bin/sh

git pull
racket generate-mirror.rkt && aws s3 mv ./ZHS-STATIC.html s3://geph-mirror/
racket main.rkt
./RUN-ME.sh
