# Non-secret test environment settings. Secrets (postgres_admin_password,
# jwt_private_key_pem, jwt_public_key_pem) are NOT here — see README.md for
# how to supply them (TF_VAR_* env vars or a gitignored *.auto.tfvars).

environment = "test"
location    = "westeurope"
prefix      = "zdrive"

cors_allowed_origins = ["http://localhost:3000"]
