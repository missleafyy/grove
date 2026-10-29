#!/bin/sh
# Download the web edition's build dependencies into web/vendor (three.js, Rapier, esbuild) and link them.
set -e
cd "$(dirname "$0")"
mkdir -p vendor node_modules/@dimforge
for p in "three 0.170.0" "@dimforge/rapier3d-compat 0.14.0" "@esbuild/linux-x64 0.24.0"; do
  set -- $p
  d=vendor/$(echo "$1" | tr '/@' '__')
  mkdir -p "$d"
  curl -sL "https://registry.npmjs.org/$1/-/$(basename "$1")-$2.tgz" | tar xz -C "$d"
done
ln -sfn ../vendor/three/package node_modules/three
ln -sfn ../../vendor/_dimforge_rapier3d-compat/package node_modules/@dimforge/rapier3d-compat
