-- The tables of Polr 2.3.0b, as its Laravel migrations make them (database/migrations of cydrobolt/polr):
-- utf8 with a case-insensitive collation, timestamps that may be NULL, flags as strings in users.
CREATE TABLE users (
    id           INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    username     VARCHAR(255) NOT NULL,
    password     VARCHAR(255) NOT NULL,
    email        VARCHAR(255) NOT NULL,
    ip           TEXT         NOT NULL,
    recovery_key VARCHAR(255) NOT NULL,
    role         VARCHAR(255) NOT NULL,
    active       VARCHAR(255) NOT NULL,
    api_key      VARCHAR(255) NULL,
    api_active   TINYINT(1)   NOT NULL DEFAULT 0,
    api_quota    VARCHAR(255) NOT NULL DEFAULT '60',
    created_at   TIMESTAMP    NULL,
    updated_at   TIMESTAMP    NULL,
    deleted_at   TIMESTAMP    NULL,
    UNIQUE KEY users_username_unique (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

CREATE TABLE links (
    id            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    short_url     VARCHAR(255) NOT NULL,
    long_url      LONGTEXT     NOT NULL,
    ip            VARCHAR(255) NOT NULL,
    creator       VARCHAR(255) NOT NULL,
    clicks        INT          NOT NULL DEFAULT 0,
    secret_key    VARCHAR(255) NOT NULL,
    is_disabled   TINYINT(1)   NOT NULL DEFAULT 0,
    is_custom     TINYINT(1)   NOT NULL DEFAULT 0,
    is_api        TINYINT(1)   NOT NULL DEFAULT 0,
    created_at    TIMESTAMP    NULL,
    updated_at    TIMESTAMP    NULL,
    long_url_hash VARCHAR(10)  NULL,
    UNIQUE KEY links_short_url_unique (short_url),
    KEY links_long_url_index (long_url_hash),
    KEY api_quota_index (created_at, creator, is_api)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

CREATE TABLE clicks (
    id           INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    ip           VARCHAR(255) NOT NULL,
    country      VARCHAR(255) NULL,
    referer      VARCHAR(255) NULL,
    referer_host VARCHAR(255) NULL,
    user_agent   TEXT         NULL,
    link_id      INT UNSIGNED NOT NULL,
    created_at   TIMESTAMP    NULL,
    updated_at   TIMESTAMP    NULL,
    KEY clicks_ip_index (ip),
    KEY clicks_referer_host_index (referer_host),
    KEY clicks_link_id_index (link_id),
    CONSTRAINT clicks_link_id_foreign FOREIGN KEY (link_id) REFERENCES links (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;
