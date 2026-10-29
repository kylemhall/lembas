-- 1 up
CREATE TABLE users (
    id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    email         VARCHAR(255) NOT NULL,                  -- lower case, the identity
    name          VARCHAR(255) NOT NULL DEFAULT '',
    google_sub    VARCHAR(255) NULL,                      -- OpenID Connect subject, set at the first sign-in
    polr_username VARCHAR(255) NULL,                      -- when imported from Polr
    is_active     TINYINT(1)   NOT NULL DEFAULT 1,        -- admins can disable an account
    last_login_at DATETIME     NULL,                      -- NULL: never signed in
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY users_email (email),
    KEY users_google_sub (google_sub)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE links (
    id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    ending        VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,  -- case sensitive
    long_url      TEXT         NOT NULL,
    long_url_hash CHAR(64)     NOT NULL,                  -- sha256 hex of long_url, to find duplicates
    user_id       INT UNSIGNED NULL,                      -- NULL: anonymous link imported from Polr
    clicks        INT UNSIGNED NOT NULL DEFAULT 0,
    is_disabled   TINYINT(1)   NOT NULL DEFAULT 0,
    is_custom     TINYINT(1)   NOT NULL DEFAULT 0,
    is_api        TINYINT(1)   NOT NULL DEFAULT 0,
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY links_ending (ending),
    KEY links_user_created (user_id, created_at),
    KEY links_duplicates (user_id, long_url_hash),
    CONSTRAINT links_user_fk FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE clicks (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    link_id      INT UNSIGNED    NOT NULL,
    clicked_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    referer      VARCHAR(2048)   NULL,
    referer_host VARCHAR(255)    NULL,
    user_agent   VARCHAR(512)    NULL,
    PRIMARY KEY (id),
    KEY clicks_link_time (link_id, clicked_at),
    CONSTRAINT clicks_link_fk FOREIGN KEY (link_id) REFERENCES links (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE api_keys (
    id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id      INT UNSIGNED NOT NULL,
    label        VARCHAR(64)  NOT NULL,
    key_prefix   CHAR(12)     NOT NULL,                   -- the start of the key, to recognize it in a list
    key_hash     CHAR(64)     NOT NULL,                   -- sha256 hex: the key itself is never stored
    last_used_at DATETIME     NULL,
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY api_keys_hash (key_hash),
    KEY api_keys_user (user_id),
    CONSTRAINT api_keys_user_fk FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 1 down
DROP TABLE IF EXISTS api_keys;
DROP TABLE IF EXISTS clicks;
DROP TABLE IF EXISTS links;
DROP TABLE IF EXISTS users;
