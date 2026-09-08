environment = "staging"
location    = "westeurope"
prefix      = "zdrive"

# postgres_administrator_password is deliberately absent: pass it as
# TF_VAR_postgres_administrator_password from a secret store at apply time.
