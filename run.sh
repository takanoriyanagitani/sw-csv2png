#!/bin/sh

input(){
  echo 0,0,0,255,0,0,0,255
  echo 16,16,16,255,16,32,64,255
  echo 128,128,128,255,128,160,192,255
}

export ENV_OUT_PNG_NAME=./out.png

export ENV_PNG_WIDTH=2
export ENV_PNG_HEIGHT=3

input | ./CsvToPng

file "${ENV_OUT_PNG_NAME}"
