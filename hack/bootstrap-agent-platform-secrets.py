import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{command[0]} failed; credential-bearing output suppressed")
    return result.stdout


def certificate(directory, name, common_name, ca=None, dns_names=()):
    key = directory / f"{name}.key"
    cert = directory / f"{name}.crt"
    run(["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", str(key)])
    if ca is None:
        run(["openssl", "req", "-x509", "-new", "-key", str(key), "-out", str(cert), "-days", "3650", "-subj", f"/CN={common_name}", "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign"])
    else:
        csr = directory / f"{name}.csr"
        extensions = directory / f"{name}.ext"
        extensions.write_text("basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=" + ",".join(f"DNS:{host}" for host in dns_names) + "\n")
        run(["openssl", "req", "-new", "-key", str(key), "-out", str(csr), "-subj", f"/CN={common_name}"])
        run(["openssl", "x509", "-req", "-in", str(csr), "-CA", str(ca[0]), "-CAkey", str(ca[1]), "-CAcreateserial", "-out", str(cert), "-days", "365", "-extfile", str(extensions)])
    return cert, key


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--environment", choices=["dev", "prod"], required=True)
    parser.add_argument("--minio-admin-file", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    repo = Path(__file__).resolve().parents[1]
    doppler = ["doppler", "--project", "talos-proxmox", "--config", args.environment]
    existing = json.loads(run(doppler + ["secrets", "download", "--no-file", "--format", "json"]))
    updates = {}
    for key in ["KAGENT_POSTGRES_PASSWORD", "AGENTREGISTRY_POSTGRES_PASSWORD"]:
        if not existing.get(key):
            updates[key] = secrets.token_hex(24)
    with tempfile.TemporaryDirectory(prefix="agent-platform-") as temporary:
        directory = Path(temporary)
        tls_keys = ["SUBSTRATE_CA_CERT", "SUBSTRATE_SERVER_CERT", "SUBSTRATE_SERVER_KEY", "SUBSTRATE_SESSION_JWT_POOL", "SUBSTRATE_SESSION_CA_POOL"]
        present = [bool(existing.get(key)) for key in tls_keys]
        if any(present) and not all(present):
            raise RuntimeError("Partial Substrate credentials exist; restore or rotate the complete set")
        if not all(present):
            ca_cert, ca_key = certificate(directory, "api-ca", "substrate-api-ca")
            server_cert, server_key = certificate(directory, "server", "api.ate-system.svc", ca=(ca_cert, ca_key), dns_names=["api.ate-system.svc", "api.ate-system.svc.cluster.local", "atenet-router.ate-system.svc"])
            session_cert, session_key = certificate(directory, "session-ca", "substrate-session-ca")
            jwt_key = directory / "jwt.key"
            run(["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", str(jwt_key)])
            updates.update({
                "SUBSTRATE_CA_CERT": ca_cert.read_text(),
                "SUBSTRATE_SERVER_CERT": server_cert.read_text(),
                "SUBSTRATE_SERVER_KEY": server_key.read_text(),
                "SUBSTRATE_SESSION_JWT_POOL": json.dumps({"Authorities": [{"ID": "1", "Algorithm": "ES256", "SigningKeyPEM": jwt_key.read_text()}]}),
                "SUBSTRATE_SESSION_CA_POOL": json.dumps({"CAs": [{"ID": "1", "SigningKeyPEM": session_key.read_text(), "RootCertificatePEM": session_cert.read_text()}]}),
            })
        if args.minio_admin_file:
            if args.environment != "dev":
                raise RuntimeError("MinIO is used only by dev")
            if not shutil.which("mc"):
                raise RuntimeError("Enter a shell with minio-client before provisioning MinIO")
            admin = json.loads(args.minio_admin_file.read_text())
            mc = ["mc", "--config-dir", str(directory / "mc")]
            run(mc + ["alias", "set", "platform", "https://minio.home.phuchoang.sbs", admin["accessKey"], admin["secretKey"]])
            access_key = existing.get("OBJECT_SUBSTRATE_ACCESS_KEY_ID") or secrets.token_hex(10)
            secret_key = existing.get("OBJECT_SUBSTRATE_SECRET_ACCESS_KEY") or secrets.token_hex(24)
            run(mc + ["admin", "policy", "create", "platform", "substrate-snapshots", str(repo / "terraform/cluster/env/dev/minio-substrate-policy.json")])
            run(mc + ["admin", "user", "add", "platform", access_key, secret_key])
            run(mc + ["admin", "policy", "attach", "platform", "substrate-snapshots", "--user", access_key])
            updates.update({"OBJECT_SUBSTRATE_ACCESS_KEY_ID": access_key, "OBJECT_SUBSTRATE_SECRET_ACCESS_KEY": secret_key})
        if updates:
            payload = directory / "secrets.json"
            payload.write_text(json.dumps(updates))
            run(doppler + ["secrets", "upload", str(payload)])
        ca = updates.get("SUBSTRATE_CA_CERT", existing.get("SUBSTRATE_CA_CERT"))
        destination = repo / f"apps/components/substrate/environments/{args.environment}/ateapi-ca.crt"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(ca)
        destination.chmod(0o644)
    print(f"{args.environment}: saved {len(updates)} credential entries to Doppler; wrote public CA certificate")


if __name__ == "__main__":
    main()
