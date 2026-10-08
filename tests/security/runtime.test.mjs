import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { rootCertificates } from 'node:tls';
import { after, test } from 'node:test';

const service = process.env.PCCS_SERVICE_DIR || '/opt/intel/pccs';
const load = path => import(pathToFileURL(resolve(service, path)).href);
const { getSSLConfig } = await load('utils/mysqlTls.js');
const directory = mkdtempSync(join(tmpdir(), 'pccs-tls-'));
after(() => rmSync(directory, { recursive: true, force: true }));

test('required MySQL TLS rejects absent, missing and malformed CAs', () => {
    for (const ca of [undefined, '', join(directory, 'missing')]) {
        assert.throws(() => getSSLConfig({ required: true, ca }));
    }
    for (const contents of ['', 'not a certificate', '-----BEGIN CERTIFICATE-----\ninvalid\n-----END CERTIFICATE-----']) {
        const ca = join(directory, 'invalid.pem');
        writeFileSync(ca, contents);
        assert.throws(() => getSSLConfig({ required: true, ca }));
    }
});

test('required MySQL TLS validates every CA and enables identity verification', () => {
    const ca = join(directory, 'ca.pem');
    writeFileSync(ca, rootCertificates.slice(0, 2).join('\n'));
    const options = getSSLConfig({ required: true, ca });
    assert.equal(options.ssl.rejectUnauthorized, true);
    assert.equal(options.ssl.verifyIdentity, true);
    assert.match(options.ssl.ca, /BEGIN CERTIFICATE/);
});

test('plaintext is an explicit TLS opt-out', () => {
    assert.equal(getSSLConfig({ required: false }), null);
});

const admin = randomBytes(32).toString('hex');
const user = randomBytes(32).toString('hex');
process.env.NODE_CONFIG = JSON.stringify({
    AdminTokenHash: createHash('sha512').update(admin).digest('hex'),
    UserTokenHash: createHash('sha512').update(user).digest('hex'),
});
const auth = await load('middleware/auth.js');
test('configured tokens authenticate only their intended role', () => {
    for (const [validator, header, token] of [
        [auth.validateAdmin, 'admin-token', admin],
        [auth.validateUser, 'user-token', user],
    ]) {
        let accepted = false;
        validator({ headers: { [header]: token } }, {}, () => { accepted = true; });
        assert.equal(accepted, true);
        for (const bad of ['admin_password', 'user_password', header === 'admin-token' ? user : admin, '']) {
            assert.throws(() => validator({ headers: { [header]: bad } }, {}, () => {
                assert.fail('Rejected token was accepted');
            }));
        }
    }
});

test('MySQL connections use verified TLS and reject the wrong CA/hostname', {
    skip: !process.env.MYSQL_TEST_HOST,
}, async () => {
    const { default: mysql } = await load('node_modules/mysql2/promise.js');
    const config = {
        host: process.env.MYSQL_TEST_HOST,
        user: 'pccs', password: process.env.MYSQL_TEST_PASSWORD,
        database: 'pccs', connectTimeout: 5000,
    };
    const tls = getSSLConfig({ required: true, ca: '/mysql-certs/ca.crt' });
    const connection = await mysql.createConnection({ ...config, ...tls });
    try {
        const [rows] = await connection.query("SHOW SESSION STATUS LIKE 'Ssl_cipher'");
        assert.ok(rows[0].Value, 'MySQL connection must negotiate TLS');
    } finally {
        await connection.end();
    }
    async function rejectsConnection(options) {
        await assert.rejects(async () => {
            const unexpected = await mysql.createConnection(options);
            await unexpected.end();
            assert.fail('Unverified MySQL connection succeeded');
        }, error => error.code !== 'ERR_ASSERTION');
    }
    await rejectsConnection({ ...config, ...tls, host: 'wrong-mysql-name' });
    await rejectsConnection({ ...config, ssl: { ...tls.ssl, ca: rootCertificates[0] } });
    await rejectsConnection(config); // server requires encrypted transport
});
