#!/usr/bin/env python3
"""Regression tests for the generated authentication and MySQL TLS configuration."""
import base64
import hashlib
import json
import secrets
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml


def digest(token):
    return hashlib.sha512(token.encode()).hexdigest()


class ChartSecurity(unittest.TestCase):
    def setUp(self):
        self.values = {"pccsConfig": {
            "apiKey": "test-api-key",
            "adminTokenHash": digest(secrets.token_hex(32)),
            "userTokenHash": digest(secrets.token_hex(32)),
        }}

    def render(self, error=None):
        with tempfile.TemporaryDirectory() as directory:
            filename = Path(directory) / "values.yaml"
            filename.write_text(yaml.safe_dump(self.values))
            result = subprocess.run(
                ["helm", "template", "pccs", "charts/pccs", "--namespace", "pccs", "-f", str(filename)],
                capture_output=True, text=True, check=False,
            )
        if error:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(error, result.stderr)
            return None
        self.assertEqual(result.returncode, 0, result.stderr)
        objects = {obj["kind"] + "/" + obj["metadata"]["name"]: obj
                   for obj in yaml.safe_load_all(result.stdout) if obj}
        config = json.loads(base64.b64decode(objects["Secret/pccs-config"]["data"]["default.json"]))
        pod = objects["StatefulSet/pccs"]["spec"]["template"]["spec"]
        return config, pod

    def test_missing_tokens(self):
        for role in ("adminTokenHash", "userTokenHash"):
            with self.subTest(role=role):
                original = self.values["pccsConfig"].pop(role)
                self.render(error=role + " must be set")
                self.values["pccsConfig"][role] = original

    def test_malformed_tokens(self):
        for value in ("not-a-hash", "a" * 127, "z" * 128):
            with self.subTest(value=value):
                self.values["pccsConfig"]["adminTokenHash"] = value
                self.render(error="128 hexadecimal characters")

    def test_example_tokens_rejected_for_either_role(self):
        for role in ("adminTokenHash", "userTokenHash"):
            for token in ("admin_password", "user_password"):
                with self.subTest(role=role, token=token):
                    original = self.values["pccsConfig"][role]
                    self.values["pccsConfig"][role] = digest(token).upper()
                    self.render(error="published example token")
                    self.values["pccsConfig"][role] = original

    def test_roles_cannot_share_token(self):
        self.values["pccsConfig"]["userTokenHash"] = self.values["pccsConfig"]["adminTokenHash"].upper()
        self.render(error="must use different tokens")

    def test_valid_tokens_and_json_escaping(self):
        self.values["pccsConfig"]["apiKey"] = 'quotes" backslash\\ newline\n'
        self.values["pccsConfig"]["userTokenHash"] = self.values["pccsConfig"]["userTokenHash"].upper()
        config, pod = self.render()
        self.assertEqual(config["ApiKey"], self.values["pccsConfig"]["apiKey"])
        self.assertEqual(config["UserTokenHash"], self.values["pccsConfig"]["userTokenHash"].lower())
        self.assertNotIn("mysql", config)
        self.assertNotIn("mysql-ca", {v["name"] for v in pod["volumes"]})

    def test_mysql_requires_ca(self):
        self.values["pccsConfig"]["storage"] = {"dialect": "mysql"}
        self.render(error="caSecretName is required")

    def test_mysql_tls_reaches_driver_config_and_pod(self):
        self.values["pccsConfig"]["storage"] = {
            "dialect": "mysql", "password": 'secret"with\\characters',
            "ssl": {"required": True, "caSecretName": "database-ca"},
        }
        config, pod = self.render()
        self.assertNotIn("ssl", config)
        self.assertTrue(config["mysql"]["ssl"]["required"])
        self.assertEqual(config["mysql"]["password"], 'secret"with\\characters')
        volume = next(v for v in pod["volumes"] if v["name"] == "mysql-ca")
        self.assertEqual(volume["secret"]["secretName"], "database-ca")
        self.assertEqual(volume["secret"]["items"], [{"key": "ca.crt", "path": "ca.crt"}])
        mount = next(m for m in pod["containers"][0]["volumeMounts"] if m["name"] == "mysql-ca")
        self.assertTrue(mount["readOnly"])
        self.assertEqual(config["mysql"]["ssl"]["ca"], mount["mountPath"] + "/ca.crt")

    def test_mysql_plaintext_requires_explicit_opt_out(self):
        self.values["pccsConfig"]["storage"] = {"dialect": "mysql", "ssl": {"required": False}}
        config, pod = self.render()
        self.assertFalse(config["mysql"]["ssl"]["required"])
        self.assertNotIn("mysql-ca", {v["name"] for v in pod["volumes"]})


if __name__ == "__main__":
    unittest.main()
