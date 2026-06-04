-- zDrive database initialization
-- Creates schemas for each microservice (logical separation, shared server)

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS files;
CREATE SCHEMA IF NOT EXISTS sync;
CREATE SCHEMA IF NOT EXISTS photos;

-- Grant usage to the application user
GRANT ALL PRIVILEGES ON SCHEMA auth TO zdrive;
GRANT ALL PRIVILEGES ON SCHEMA files TO zdrive;
GRANT ALL PRIVILEGES ON SCHEMA sync TO zdrive;
GRANT ALL PRIVILEGES ON SCHEMA photos TO zdrive;
