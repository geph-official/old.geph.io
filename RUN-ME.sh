#!/bin/sh

git pull
racket generate-mirror.rkt && rclone copy ZHS-STATIC.html b2:geph-dl/ && rm ZHS-STATIC.html
racket main.rkt
./RUN-ME.sh
