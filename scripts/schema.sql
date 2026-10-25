CREATE TABLE IF NOT EXISTS accounts (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    email VARCHAR(255) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_accounts_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS personas (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    account_id BIGINT UNSIGNED NOT NULL,
    blaze_id BIGINT UNSIGNED NOT NULL,
    name VARCHAR(64) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at DATETIME NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_personas_blaze_id (blaze_id),
    UNIQUE KEY uq_personas_name (name),
    CONSTRAINT fk_personas_account FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sessions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    persona_id BIGINT UNSIGNED NOT NULL,
    session_key VARCHAR(128) NOT NULL,
    session_kind VARCHAR(24) NOT NULL DEFAULT 'legacy',
    credential_key CHAR(64) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_sessions_key (session_key),
    KEY ix_sessions_persona (persona_id),
    KEY ix_sessions_credential (credential_key),
    CONSTRAINT fk_sessions_persona FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS launcher_credentials (
    public_key CHAR(64) NOT NULL,
    persona_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (public_key),
    UNIQUE KEY uq_launcher_credential_persona (persona_id),
    CONSTRAINT fk_launcher_credential_persona FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS launcher_claims (
    claim_hash CHAR(64) NOT NULL,
    persona_name VARCHAR(64) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL,
    PRIMARY KEY (claim_hash),
    KEY ix_launcher_claim_persona (persona_name),
    KEY ix_launcher_claim_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS identity_aliases (
    alias_key VARCHAR(255) NOT NULL,
    persona_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (alias_key),
    KEY ix_identity_alias_persona (persona_id),
    CONSTRAINT fk_identity_alias_persona FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS friends (
    persona_id BIGINT UNSIGNED NOT NULL,
    friend_persona_id BIGINT UNSIGNED NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'accepted',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (persona_id, friend_persona_id),
    CONSTRAINT fk_friends_persona FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE CASCADE,
    CONSTRAINT fk_friends_friend FOREIGN KEY (friend_persona_id) REFERENCES personas(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS stats (
    persona_id BIGINT UNSIGNED NOT NULL,
    category VARCHAR(64) NOT NULL,
    stat_key VARCHAR(128) NOT NULL,
    stat_value BIGINT NOT NULL DEFAULT 0,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (persona_id, category, stat_key),
    CONSTRAINT fk_stats_persona FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS leaderboards (
    board_key VARCHAR(96) NOT NULL,
    event_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
    persona_id BIGINT UNSIGNED NOT NULL,
    score BIGINT NOT NULL DEFAULT 0,
    metadata_json LONGTEXT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (board_key, event_id, persona_id),
    CONSTRAINT fk_leaderboards_persona FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS autolog_stories (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    persona_id BIGINT UNSIGNED NOT NULL,
    story_type VARCHAR(64) NOT NULL,
    payload_json LONGTEXT NOT NULL,
    viewed TINYINT(1) NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ix_autolog_stories_persona (persona_id),
    CONSTRAINT fk_autolog_stories_persona FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS game_sessions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    blaze_game_id BIGINT UNSIGNED NULL,
    host_persona_id BIGINT UNSIGNED NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'created',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_game_sessions_blaze (blaze_game_id),
    CONSTRAINT fk_game_sessions_host FOREIGN KEY (host_persona_id) REFERENCES personas(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS server_state (
    state_key VARCHAR(64) NOT NULL,
    state_value TEXT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (state_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS game_reports (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    persona_id BIGINT UNSIGNED NULL,
    game_type VARCHAR(64) NOT NULL,
    payload_sha256 CHAR(64) NOT NULL,
    payload_hex MEDIUMTEXT NOT NULL,
    results_json MEDIUMTEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_game_reports_payload (payload_sha256),
    KEY ix_game_reports_persona (persona_id),
    CONSTRAINT fk_game_reports_persona FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS locker_contents (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    persona_id BIGINT UNSIGNED NOT NULL,
    category VARCHAR(64) NOT NULL,
    name VARCHAR(128) NOT NULL DEFAULT '',
    description VARCHAR(512) NOT NULL DEFAULT '',
    attributes_json MEDIUMTEXT NOT NULL,
    sub_names VARCHAR(512) NOT NULL DEFAULT '',
    permission INT NOT NULL DEFAULT 0,
    status INT NOT NULL DEFAULT 1,
    size_bytes INT NOT NULL DEFAULT 0,
    use_count INT UNSIGNED NOT NULL DEFAULT 0,
    upload_token CHAR(32) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ix_locker_owner (persona_id, category),
    KEY ix_locker_category (category, status),
    CONSTRAINT fk_locker_persona FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS locker_ratings (
    content_id INT UNSIGNED NOT NULL,
    persona_id BIGINT UNSIGNED NOT NULL,
    rating INT NOT NULL,
    rated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (content_id, persona_id),
    KEY ix_locker_ratings_persona (persona_id),
    CONSTRAINT fk_locker_ratings_content FOREIGN KEY (content_id) REFERENCES locker_contents(id) ON DELETE CASCADE,
    CONSTRAINT fk_locker_ratings_persona FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
