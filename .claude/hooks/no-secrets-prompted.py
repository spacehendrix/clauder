#!/usr/bin/env python3
import json
import sys
import re
import base64
from utils.trace_decision import log_decision

def get_preferences():
    """Read preferences from .claude/preferences.json."""
    try:
        with open('.claude/preferences.json', 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def is_likely_secret(text):
    """Check if text looks like a secret based on various heuristics."""
    if not text or len(text.strip()) < 10:
        return False, None
    
    text = text.strip()
    
    # Check for common secret patterns
    secret_patterns = [
        # API keys and tokens
        (r'^[a-zA-Z0-9]{32,}$', 'long_alphanumeric'),  # Long alphanumeric strings
        (r'^sk-[a-zA-Z0-9]{20,}$', 'api_key'),  # OpenAI API keys
        (r'^sk_[a-zA-Z0-9]{24,}$', 'secret_key'),  # Stripe secret keys
        (r'^pk_[a-zA-Z0-9]{24,}$', 'public_key'),  # Stripe public keys
        (r'^AKIA[a-zA-Z0-9]{16,}$', 'access_key'),  # AWS Access Key
        (r'^ASIA[a-zA-Z0-9]{16,}$', 'temp_access_key'),  # AWS Temporary Access Key
        (r'^ghp_[a-zA-Z0-9]{36}$', 'personal_token'),  # GitHub personal access tokens
        (r'^gho_[a-zA-Z0-9]{36}$', 'oauth_token'),  # GitHub OAuth tokens
        (r'^ghu_[a-zA-Z0-9]{36}$', 'user_server_token'),  # GitHub user-to-server tokens
        (r'^ghs_[a-zA-Z0-9]{36}$', 'server_token'),  # GitHub server-to-server tokens
        (r'^ghr_[a-zA-Z0-9]{36}$', 'refresh_token'),  # GitHub refresh tokens
        (r'^xoxb-[a-zA-Z0-9-]+$', 'bot_token'),  # Slack Bot Token
        (r'^xoxp-[a-zA-Z0-9-]+$', 'user_token'),  # Slack User Token
        (r'^xoxa-[a-zA-Z0-9-]+$', 'app_token'),  # Slack App Token
        (r'^xoxr-[a-zA-Z0-9-]+$', 'config_token'),  # Slack Config Token
        (r'^AIza[a-zA-Z0-9]{35}$', 'api_key'),  # Google API Key
        (r'^ya29\.[a-zA-Z0-9_-]+$', 'oauth_token'),  # Google OAuth Token
        (r'^1//[a-zA-Z0-9_-]+$', 'oauth_refresh'),  # Google OAuth Refresh Token
        (r'^[0-9]+-[0-9A-Za-z_]{32}\.apps\.googleusercontent\.com$', 'oauth_client_id'),  # Google OAuth Client ID
        (r'^[0-9]{12}:aws:iam::[0-9]{12}:user/[a-zA-Z0-9_-]+$', 'user_arn'),  # AWS User ARN
        (r'^arn:aws:iam::[0-9]{12}:role/[a-zA-Z0-9_-]+$', 'role_arn'),  # AWS Role ARN
        (r'^[a-zA-Z0-9]{40}$', 'sha1_hash'),  # SHA-1 hashes (like git commit hashes)
        (r'^[a-zA-Z0-9]{64}$', 'sha256_hash'),  # SHA-256 hashes
        (r'^[a-zA-Z0-9]{128}$', 'sha512_hash'),  # SHA-512 hashes
        
        # JWT tokens
        (r'^eyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]*$', 'jwt_token'),
        
        # Base64 encoded strings (likely secrets)
        (r'^[A-Za-z0-9+/]{75,}={0,2}$', 'base64_encoded'),
        
        # UUIDs (might be secrets)
        (r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', 'uuid'),
        
        # Private keys (PEM format)
        (r'^-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----', 'private_key_pem'),
        (r'^-----BEGIN\s+OPENSSH\s+PRIVATE\s+KEY-----', 'openssh_private_key'),
        (r'^-----BEGIN\s+DSA\s+PRIVATE\s+KEY-----', 'dsa_private_key'),
        (r'^-----BEGIN\s+EC\s+PRIVATE\s+KEY-----', 'ec_private_key'),
        (r'^-----BEGIN\s+PGP\s+PRIVATE\s+KEY\s+BLOCK-----', 'pgp_private_key'),
        (r'^-----BEGIN\s+PGP\s+PUBLIC\s+KEY\s+BLOCK-----', 'pgp_public_key'),
        (r'^-----BEGIN\s+PGP\s+MESSAGE-----', 'pgp_message'),
        (r'^-----BEGIN\s+PUBLIC\s+KEY-----', 'public_key_pem'),
        (r'^-----BEGIN\s+CERTIFICATE-----', 'certificate'),
        
        # SSH keys
        (r'^ssh-rsa\s+[A-Za-z0-9+/]+[=]*\s+[^@\s]+@[^@\s]+$', 'ssh_rsa_key'),
        (r'^ssh-ed25519\s+[A-Za-z0-9+/]+[=]*\s+[^@\s]+@[^@\s]+$', 'ssh_ed25519_key'),
        (r'^ssh-dss\s+[A-Za-z0-9+/]+[=]*\s+[^@\s]+@[^@\s]+$', 'ssh_dss_key'),
        
        # Database connection strings
        (r'^(postgresql|mysql|mongodb|redis)://[^@]+@[^:]+:\d+', 'database_connection'),
        (r'^mongodb\+srv://[^@]+@[^/]+', 'mongodb_srv_connection'),
        
        # AWS credentials
        (r'^[A-Za-z0-9/+=]{75,}$', 'secret_key'),  # AWS secret access key
        
        # Generic high-entropy strings (75+ chars)
        (r'^[a-f0-9]{75,}$', 'hex_string'),  # Hex strings
        (r'^[A-Z0-9]{75,}$', 'uppercase_alphanumeric'),  # Uppercase alphanumeric
    ]
    
    for pattern, pattern_name in secret_patterns:
        if re.match(pattern, text, re.IGNORECASE):
            return True, pattern_name
    
    # Check for high entropy (random-looking strings)
    if len(text) > 20:
        # If the text contains spaces, it's likely natural language, not a secret
        if ' ' in text:
            return False, None
            
        # Count character types
        has_upper = bool(re.search(r'[A-Z]', text))
        has_lower = bool(re.search(r'[a-z]', text))
        has_digit = bool(re.search(r'\d', text))
        has_special = bool(re.search(r'[^A-Za-z0-9]', text))
        
        # If it has multiple character types and is long, it might be a secret
        char_types = sum([has_upper, has_lower, has_digit, has_special])
        if (char_types >= 3 and len(text) > 75) or (char_types >= 2 and len(text) >= 40):
            return True, 'high_entropy_string'
    
    return False, None

def check_quoted_content(text):
    """Check for secrets in quoted content."""
    # Find all quoted strings
    quoted_patterns = [
        r'"([^"]{10,})"',  # Double quoted strings
        r"'([^']{10,})'",  # Single quoted strings
        r'`([^`]{10,})`',  # Backtick quoted strings
    ]
    
    for pattern in quoted_patterns:
        matches = re.findall(pattern, text)
        for match in matches:
            is_secret, pattern_name = is_likely_secret(match)
            if is_secret:
                return True, pattern_name, match
    
    return False, None, None

def check_for_sensitive_keywords(text):
    """Check for sensitive keywords that might indicate secrets."""
    sensitive_keywords = [
        r'(?i)\b(password|secret|key|token|private|pwd|encrypt|enc)\s*[:=]',
        r'(?i)\b(api_key|access_key|secret_key|private_key)\s*[:=]',
        r'(?i)\b(auth|authentication|authorization)\s*[:=]',
        r'(?i)\b(credential|cred)\s*[:=]',
        r'(?i)\b(login|username|user)\s*[:=]',
        r'(?i)\b(database|db|connection)\s*[:=]',
        r'(?i)\b(host|port|endpoint|url)\s*[:=]',
        r'(?i)\b(session|cookie)\s*[:=]',
        r'(?i)\b(signature|sign)\s*[:=]',
        r'(?i)\b(hash|digest|checksum)\s*[:=]',
    ]
    
    for pattern in sensitive_keywords:
        if re.search(pattern, text):
            return True
    
    return False

# Load input from stdin
try:
    input_data = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
    sys.exit(1)

prompt = input_data.get("prompt", "")

# Opt-in via .claude/preferences.json → prompt_secret_safety_checks.enabled
preferences = get_preferences()
prompt_secret_safety_checks = preferences.get('prompt_secret_safety_checks', {})
if not prompt_secret_safety_checks.get('enabled', False):
    output = {
        "reason": "Prompt secret safety checks disabled in preferences. Proceeding."
    }
    print(json.dumps(output))
    sys.exit(0)

# Check for sensitive keywords FIXME: (Disabled for false positives)
# if check_for_sensitive_keywords(prompt):
#     output = {
#         "continue": False,
#         "stopReason": "Security policy violation: Prompt contains sensitive keywords. Please rephrase your request without sensitive information.",
#         "suppressOutput": True,
#         "decision": "block",
#         "reason": "Security policy violation: Prompt contains sensitive keywords. Please rephrase your request without sensitive information."
#     }
#     print(json.dumps(output))
#     sys.exit(2)

# Check for secrets in quoted content
found_secret, pattern_name, match_text = check_quoted_content(prompt)
if found_secret:
    # Show first 8 characters with ellipsis
    preview = match_text[:8] + "..." if len(match_text) > 8 else match_text
    output = {
        "continue": False,
        "stopReason": "Security policy violation: Quoted content contains potential secrets. Please rephrase your request without sensitive information. You may reference secrets from a different directory or vault (e.g. doppler, hashicorp vault, unix pass).",
        "suppressOutput": True,
        "decision": "block",
        "reason": f"Security policy violation: Quoted content contains potential secrets. Pattern triggered: {pattern_name} (starts with: {preview}). Please rephrase your request without sensitive information. You may reference secrets from a different directory or vault  (e.g. doppler, hashicorp vault, unix pass)."
    }
    log_decision(output, operation_type="quoted_secrets_decision")
    print(json.dumps(output))
    sys.exit(2)

# Check for long strings that might be secrets
words = prompt.split()
for word in words:
    is_secret, pattern_name = is_likely_secret(word)
    if is_secret:
        # Show first 8 characters with ellipsis
        preview = word[:8] + "..." if len(word) > 8 else word
        output = {
            "continue": False,
            "stopReason": "Security policy violation: Prompt contains potential secret values. Please rephrase your request without sensitive information.",
            "suppressOutput": True,
            "decision": "block",
            "reason": f"Security policy violation: Prompt contains potential secret values. Pattern triggered: {pattern_name} (starts with: {preview}). Please rephrase your request without sensitive information."
        }
        log_decision(output, operation_type="word_secrets_decision")
        print(json.dumps(output))
        sys.exit(2)

# Allow the prompt to proceed
output = {
    "reason": "No sensitive information detected in prompt. Proceeding."
}
print(json.dumps(output))
sys.exit(0)