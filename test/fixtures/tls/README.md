Self-signed certificates for the TLS trust tests (test/tls_trust_test.dart).
Test-only keys: never use them anywhere else. Made with:

    openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
      -subj "/CN=teamtalkx-test-a" -keyout a.key.pem -out a.cert.pem
