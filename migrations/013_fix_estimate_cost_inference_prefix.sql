-- Fix estimate_cost_usd to handle Bedrock inference profile model IDs.
--
-- Bedrock inference profiles are referenced with IDs like:
--   au.anthropic.claude-opus-5
--   us.anthropic.claude-sonnet-5-20260601
--   eu.anthropic.claude-haiku-4-5
--
-- When users (or Claude Code) specify such an ID as the model name, it is
-- stored verbatim in spend_log.model.  The previous version of the function
-- only matched on a bare prefix like "claude-opus-5", so any spend_log row
-- whose model begins with a regional qualifier was silently unpriced.
--
-- Fix: strip the leading "<region>.<vendor>." segment before doing the LIKE
-- match.  regexp_replace leaves IDs that are already bare (e.g.
-- "claude-opus-4-7-20260401") unchanged because the pattern requires exactly
-- two dot-delimited segments followed by another dot.

CREATE OR REPLACE FUNCTION estimate_cost_usd(
    p_model TEXT,
    p_input_tokens INTEGER,
    p_output_tokens INTEGER,
    p_cache_read_tokens INTEGER DEFAULT 0,
    p_cache_write_tokens INTEGER DEFAULT 0
) RETURNS DOUBLE PRECISION AS $$
DECLARE
    r RECORD;
    clean_model TEXT;
BEGIN
    -- Strip optional "<region>.<vendor>." prefix from Bedrock inference profile
    -- IDs (e.g. "au.anthropic." or "us.anthropic.") so that they resolve to
    -- the same model_prefix rows as bare IDs like "claude-opus-5".
    clean_model := regexp_replace(p_model, '^[a-z0-9]+\.[a-z]+\.', '');

    SELECT input_rate, output_rate, cache_read_rate, cache_write_rate
    INTO r FROM model_pricing
    WHERE clean_model LIKE model_prefix || '%'
    ORDER BY length(model_prefix) DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    RETURN (p_input_tokens * r.input_rate
          + p_output_tokens * r.output_rate
          + p_cache_read_tokens * r.cache_read_rate
          + p_cache_write_tokens * r.cache_write_rate) / 1000000.0;
END;
$$ LANGUAGE plpgsql STABLE;
