-- zDrive database initialization
-- Creates schemas for each microservice (logical separation, shared server)

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS files;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS sync;
CREATE SCHEMA IF NOT EXISTS photos;
CREATE SCHEMA IF NOT EXISTS notifications;

-- Grant usage to the application user
GRANT ALL PRIVILEGES ON SCHEMA auth TO zdrive;
GRANT ALL PRIVILEGES ON SCHEMA files TO zdrive;
GRANT ALL PRIVILEGES ON SCHEMA storage TO zdrive;
GRANT ALL PRIVILEGES ON SCHEMA sync TO zdrive;
GRANT ALL PRIVILEGES ON SCHEMA photos TO zdrive;
GRANT ALL PRIVILEGES ON SCHEMA notifications TO zdrive;
