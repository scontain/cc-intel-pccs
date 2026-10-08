#!/usr/bin/env bash
set -euo pipefail

: "${PCCS_TEST_IMAGE:?Set PCCS_TEST_IMAGE to the built PCCS image}"
workdir=$(mktemp -d)
network="pccs-mysql-security-${GITHUB_RUN_ID:-$$}"
container="$network-db"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$workdir"
}
trap cleanup EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=PCCS-test-CA \
  -keyout "$workdir/ca.key" -out "$workdir/ca.crt" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -subj /CN=mysql-server \
  -keyout "$workdir/server.key" -out "$workdir/server.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:mysql-server\nextendedKeyUsage=serverAuth\n' > "$workdir/extensions"
openssl x509 -req -in "$workdir/server.csr" -CA "$workdir/ca.crt" -CAkey "$workdir/ca.key" \
  -CAcreateserial -days 1 -extfile "$workdir/extensions" -out "$workdir/server.crt" >/dev/null 2>&1
# Only disposable test certificates are mounted; the signer key stays on the runner.
mkdir "$workdir/server" "$workdir/client"
cp "$workdir/ca.crt" "$workdir/server.crt" "$workdir/server.key" "$workdir/server/"
cp "$workdir/ca.crt" "$workdir/client/"
chmod 755 "$workdir" "$workdir/server" "$workdir/client"
chmod 644 "$workdir/server/"* "$workdir/client/"*
export MYSQL_TEST_PASSWORD
MYSQL_TEST_PASSWORD=$(openssl rand -hex 32)

docker network create "$network" >/dev/null
docker run -d --name "$container" --network "$network" \
  --network-alias mysql-server --network-alias wrong-mysql-name \
  -e MYSQL_ROOT_PASSWORD="$MYSQL_TEST_PASSWORD" -e MYSQL_DATABASE=pccs \
  -e MYSQL_USER=pccs -e MYSQL_PASSWORD="$MYSQL_TEST_PASSWORD" \
  -v "$workdir/server:/mysql-certs:ro" mysql:8.4 \
  --ssl-ca=/mysql-certs/ca.crt --ssl-cert=/mysql-certs/server.crt \
  --ssl-key=/mysql-certs/server.key --require-secure-transport=ON >/dev/null
ready=false
for _ in $(seq 1 60); do
  if docker exec "$container" mysqladmin ping --host=127.0.0.1 --silent >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
if [ "$ready" != true ]; then
  docker logs "$container"
  exit 1
fi
docker run --rm --network "$network" \
  -e MYSQL_TEST_HOST=mysql-server -e MYSQL_TEST_PASSWORD \
  -v "$workdir/client:/mysql-certs:ro" \
  -v "$PWD/tests/security:/security:ro" \
  --entrypoint /usr/bin/node "$PCCS_TEST_IMAGE" --test /security/runtime.test.mjs
