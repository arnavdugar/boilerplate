#!/bin/sh

set -eu

(cd api && go generate ./...)
(cd web && pnpm run generate:api)
