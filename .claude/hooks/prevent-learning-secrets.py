#!/usr/bin/env python3
"""
Script to check if a project is safe for indexing.
Returns 0 (safe) or 1 (unsafe) based on presence of sensitive files/directories.
"""

import sys
import argparse
import fnmatch
import json
import re
import math
from pathlib import Path
from typing import List, Tuple
from collections import Counter
from utils.trace_decision import log_decision

def get_preferences():
    """Read preferences from .claude/preferences.json."""
    try:
        with open('.claude/preferences.json', 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

class Colors:
    """ANSI color codes for terminal output."""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    GRAY = '\033[0;90m'
    NC = '\033[0m'  # No Color


def print_status(color: str, message: str) -> None:
    """Print a colored status message."""
    print(f"{color}{message}{Colors.NC}")


class ProjectSafetyChecker:
    """Check if a project directory is safe for indexing."""
    
    def __init__(self):
        # Sensitive patterns to check (from .claude/.ignore)
        self.sensitive_patterns = [
            "secret",
            "private",
            ".env.",
            ".env",
            ".env.local",
            ".env.example",
            ".env.dev",
            ".env.development",
            ".env.stage",
            ".env.staging",
            ".env.sandbox",
            ".env.preprod",
            ".env.prod",
            ".env.production"
        ]
        
        # Additional patterns that might contain secrets
        self.secret_indicators = [
            "*key*",
            "*password*",
            "*token*",
            "*secret*",
            "*private*",
            "*privk*",
        ]
        
        # Load exclusion patterns (will be loaded when check_project_safety is called)
        self.exclusion_patterns = []
    
    def _load_exclusion_patterns(self, project_path: Path) -> List[str]:
        """Load exclusion patterns from .claude/.exclude_security_checks file."""
        exclusion_file = project_path / ".claude" / ".exclude_security_checks"
        patterns = []
        
        if 'standalone' in sys.argv:  # Debug output only in standalone mode
            print_status(Colors.GRAY, f"DEBUG: Looking for exclusion file at: {exclusion_file}")
            print_status(Colors.GRAY, f"DEBUG: Current working directory: {Path.cwd()}")
            print_status(Colors.GRAY, f"DEBUG: Project path: {project_path}")
        
        if exclusion_file.exists():
            try:
                with open(exclusion_file, 'r', encoding='utf-8') as f:
                    for line in f:
                        line = line.strip()
                        # Skip empty lines and comments
                        if line and not line.startswith('#'):
                            patterns.append(line)
                if 'standalone' in sys.argv:  # Debug output only in standalone mode
                    print_status(Colors.GRAY, f"DEBUG: Loaded exclusion patterns: {patterns}")
            except (UnicodeDecodeError, PermissionError, OSError) as e:
                print(f"Warning: Could not read exclusion file {exclusion_file}: {e}")
        else:
            if 'standalone' in sys.argv:  # Debug output only in standalone mode
                print_status(Colors.GRAY, f"DEBUG: Exclusion file not found: {exclusion_file}")
        
        return patterns
    
    def _is_excluded(self, file_path: Path, project_path: Path) -> bool:
        """Check if a file or directory should be excluded from security checks."""
        relative_path = file_path.relative_to(project_path)
        
        for pattern in self.exclusion_patterns:
            # Handle directory patterns (ending with /)
            if pattern.endswith('/'):
                # Remove trailing slash for comparison
                dir_pattern = pattern.rstrip('/')
                # Check if the file is inside this directory
                if str(relative_path).startswith(dir_pattern + '/') or str(relative_path) == dir_pattern:
                    if 'standalone' in sys.argv:  # Debug output only in standalone mode
                        print_status(Colors.GRAY, f"DEBUG: Excluded {relative_path} by directory pattern {pattern}")
                    return True
            else:
                # Check if the pattern matches the file/directory name or path
                if fnmatch.fnmatch(str(relative_path), pattern) or fnmatch.fnmatch(file_path.name, pattern):
                    if 'standalone' in sys.argv:  # Debug output only in standalone mode
                        print_status(Colors.GRAY, f"DEBUG: Excluded {relative_path} by pattern {pattern}")
                    return True
                
                # Check if any parent directory matches the pattern
                for parent in relative_path.parents:
                    if fnmatch.fnmatch(str(parent), pattern):
                        if 'standalone' in sys.argv:  # Debug output only in standalone mode
                            print_status(Colors.GRAY, f"DEBUG: Excluded {relative_path} by parent pattern {pattern}")
                        return True
        
        return False
    
    def check_exact_matches(self, project_path: Path) -> List[Tuple[str, str]]:
        """Check for exact matches of sensitive patterns."""
        found_items = []
        
        for pattern in self.sensitive_patterns:
            item_path = project_path / pattern
            if item_path.exists() and not self._is_excluded(item_path, project_path):
                found_items.append((pattern, str(item_path.relative_to(project_path))))
        
        return found_items
    
    def check_pattern_matches(self, project_path: Path) -> List[Tuple[str, str]]:
        """Check for files/directories containing sensitive patterns."""
        found_patterns = []
        
        for pattern in self.sensitive_patterns:
            # Skip exact matches we already checked
            if (project_path / pattern).exists():
                continue
                
            # Search for files/directories containing the pattern
            for item in project_path.rglob(f"*{pattern}*"):
                if (item.is_file() or item.is_dir()) and not self._is_excluded(item, project_path):
                    found_patterns.append((pattern, str(item.relative_to(project_path))))
                    break
        
        return found_patterns
    
    def check_secret_indicators(self, project_path: Path) -> List[Tuple[str, str]]:
        """Check for files that might contain secrets based on naming patterns."""
        found_indicators = []
        
        for indicator in self.secret_indicators:
            for item in project_path.rglob(indicator):
                if (item.is_file() or item.is_dir()) and not self._is_excluded(item, project_path):
                    found_indicators.append((indicator, str(item.relative_to(project_path))))
                    break
        
        return found_indicators
    
    def _is_false_positive_key(self, line: str) -> bool:
        """Check if a line with 'key*=' pattern is a false positive (keyframe, :key=, etc.)."""
        # Convert to lowercase for case-insensitive matching
        line_lower = line.lower()
        
        # Check for common false positives
        false_positives = [
            'keyframe',
            ':key=',
            'v-bind:key=',
            '@keyframes',
            'animation-keyframe',
            'transition-keyframe',
            'keyframe-animation',
            'keyframe-transition'
        ]
        
        for false_positive in false_positives:
            if false_positive in line_lower:
                return True
        
        return False

    def _calculate_entropy(self, text: str) -> float:
        """Calculate Shannon entropy of a string."""
        if not text:
            return 0.0
        
        # Count character frequencies
        char_counts = Counter(text)
        length = len(text)
        
        # Calculate entropy
        entropy = 0.0
        for count in char_counts.values():
            probability = count / length
            entropy -= probability * math.log2(probability)
        
        return entropy

    def _is_high_entropy(self, text: str, min_length: int = 16, min_entropy: float = 3.5) -> bool:
        """Check if a string has high entropy (indicating it might be a secret)."""
        if len(text) < min_length:
            return False
        
        # Calculate entropy
        entropy = self._calculate_entropy(text)
        
        # Check if entropy is above threshold
        if entropy >= min_entropy:
            # Additional checks to reduce false positives
            # Skip if it's mostly repeated characters or simple patterns
            if len(set(text)) < len(text) * 0.3:  # Less than 30% unique characters
                return False
            
            # Skip if it's a simple repeating pattern
            if len(text) >= 4:
                for i in range(1, len(text) // 2 + 1):
                    if text[:i] * (len(text) // i) == text[:len(text) // i * i]:
                        return False
            
            return True
        
        # Also check for character type diversity like in no-secrets-prompted.py
        if len(text) > 20:
            # If the text contains spaces, it's likely natural language, not a secret
            if ' ' in text:
                return False
                
            # Count character types
            has_upper = bool(re.search(r'[A-Z]', text))
            has_lower = bool(re.search(r'[a-z]', text))
            has_digit = bool(re.search(r'\d', text))
            has_special = bool(re.search(r'[^A-Za-z0-9]', text))
            
            # If it has multiple character types and is long, it might be a secret
            char_types = sum([has_upper, has_lower, has_digit, has_special])
            if (char_types >= 3 and len(text) > 75) or (char_types >= 2 and len(text) >= 40):
                return True
        
        return False

    def _extract_potential_secrets(self, text: str) -> List[str]:
        """Extract potential secret strings from text based on common patterns."""
        secrets = []
        
        # Common key prefixes and patterns
        key_patterns = [
            # API Keys
            r'sk-[a-zA-Z0-9]{20,}',  # OpenAI
            r'pk_[a-zA-Z0-9]{20,}',  # Stripe
            r'AKIA[a-zA-Z0-9]{16,}',  # AWS Access Key
            r'ASIA[a-zA-Z0-9]{16,}',  # AWS Temporary Access Key
            r'ghp_[a-zA-Z0-9]{36}',  # GitHub Personal Access Token
            r'gho_[a-zA-Z0-9]{36}',  # GitHub OAuth Token
            r'ghu_[a-zA-Z0-9]{36}',  # GitHub User-to-Server Token
            r'ghs_[a-zA-Z0-9]{36}',  # GitHub Server-to-Server Token
            r'ghr_[a-zA-Z0-9]{36}',  # GitHub Refresh Token
            r'xoxb-[a-zA-Z0-9-]+',   # Slack Bot Token
            r'xoxp-[a-zA-Z0-9-]+',   # Slack User Token
            r'xoxa-[a-zA-Z0-9-]+',   # Slack App Token
            r'xoxr-[a-zA-Z0-9-]+',   # Slack Config Token
            r'AIza[a-zA-Z0-9]{35}',  # Google API Key
            r'ya29\.[a-zA-Z0-9_-]+', # Google OAuth Token
            r'1//[a-zA-Z0-9_-]+',    # Google OAuth Refresh Token
            r'[0-9]+-[0-9A-Za-z_]{32}\.apps\.googleusercontent\.com',  # Google OAuth Client ID
            r'[0-9]{12}:aws:iam::[0-9]{12}:user/[a-zA-Z0-9_-]+',  # AWS ARN
            r'arn:aws:iam::[0-9]{12}:role/[a-zA-Z0-9_-]+',  # AWS Role ARN
            
            # JWT Tokens
            r'eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+',
            
            # SSH Keys
            r'ssh-rsa\s+[a-zA-Z0-9+/]+[=]*\s+[^@\s]+@[^@\s]+',
            r'ssh-ed25519\s+[a-zA-Z0-9+/]+[=]*\s+[^@\s]+@[^@\s]+',
            r'ssh-dss\s+[a-zA-Z0-9+/]+[=]*\s+[^@\s]+@[^@\s]+',
            
            # PGP Keys
            r'-----BEGIN PGP PRIVATE KEY BLOCK-----',
            r'-----BEGIN PGP PUBLIC KEY BLOCK-----',
            r'-----BEGIN PGP MESSAGE-----',
            r'-----BEGIN RSA PRIVATE KEY-----',
            r'-----BEGIN PRIVATE KEY-----',
            r'-----BEGIN PUBLIC KEY-----',
            r'-----BEGIN CERTIFICATE-----',
            
            # Generic high-entropy strings (75+ chars)
            r'[a-zA-Z0-9+/]{75,}={0,2}',  # Base64-like
            r'[a-f0-9]{75,}',             # Hex strings
            r'[A-Z0-9]{75,}',             # Uppercase alphanumeric
        ]
        
        for pattern in key_patterns:
            matches = re.findall(pattern, text, re.IGNORECASE)
            secrets.extend(matches)
        
        return secrets

    def _check_line_for_secrets(self, line: str) -> List[Tuple[str, str]]:
        """Check a single line for potential secrets."""
        findings = []
        
        # Extract potential secrets using pattern matching
        potential_secrets = self._extract_potential_secrets(line)
        
        for secret in potential_secrets:
            # Skip if it's a false positive
            if self._is_false_positive_key(line) and 'key' in line.lower():
                continue
            
            # Check if the secret has high entropy
            if self._is_high_entropy(secret):
                findings.append(('high_entropy_secret', secret))
            else:
                # Even if not high entropy, certain patterns are always suspicious
                if any(pattern in secret.lower() for pattern in ['sk-', 'pk_', 'ghp_', 'gho_', 'ghu_', 'ghs_', 'ghr_', 'xoxb-', 'xoxp-', 'xoxa-', 'xoxr-', 'AIza', 'ya29.', '1//', 'AKIA', 'ASIA']):
                    findings.append(('known_key_pattern', secret))
        
        # Also check for assignment patterns with high entropy values
        assignment_patterns = [
            r'(?:password|key|token|secret|private|privk|api_key|apikey)\s*[=:]\s*["\']([^"\']+)["\']',
            r'(?:password|key|token|secret|private|privk|api_key|apikey)\s*[=:]\s*([a-zA-Z0-9+/_-]{32,})',
        ]
        
        for pattern in assignment_patterns:
            matches = re.findall(pattern, line, re.IGNORECASE)
            for match in matches:
                if self._is_high_entropy(match):
                    findings.append(('assignment_high_entropy', match))
        
        return findings

    def check_file_contents(self, project_path: Path) -> List[Tuple[str, str, int]]:
        """Check file contents for high entropy strings and common key patterns."""
        suspicious_files = []
        
        for file_path in project_path.rglob('*'):
            if not file_path.is_file():
                continue
                
            # Skip excluded files
            if self._is_excluded(file_path, project_path):
                continue
                
            # Skip binary files and large files
            if self._is_binary_file(file_path) or file_path.stat().st_size > 1024 * 1024:
                continue
                
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()
                    
                for line_num, line in enumerate(lines, 1):
                    # Check line for secrets using new detection methods
                    findings = self._check_line_for_secrets(line)
                    
                    for finding_type, secret_value in findings:
                        relative_path = str(file_path.relative_to(project_path))
                        # Don't show the actual secret value, just the detection type
                        suspicious_files.append((relative_path, finding_type, line_num))
                        
            except (UnicodeDecodeError, PermissionError, OSError):
                continue
        
        return suspicious_files
    
    def _is_binary_file(self, file_path: Path) -> bool:
        """Check if a file is likely binary."""
        try:
            with open(file_path, 'rb') as f:
                chunk = f.read(1024)
                return b'\x00' in chunk
        except (PermissionError, OSError):
            return True
    
    def check_project_safety(self, project_path: Path, standalone: bool = False) -> Tuple[bool, dict]:
        """
        Check if a project is safe for indexing.
        
        Returns:
            Tuple of (is_safe, results_dict)
        """
        if not project_path.exists():
            raise FileNotFoundError(f"Directory '{project_path}' does not exist")
        
        if not project_path.is_dir():
            raise NotADirectoryError(f"'{project_path}' is not a directory")
        
        # Load exclusion patterns
        self.exclusion_patterns = self._load_exclusion_patterns(project_path)
        
        # Check if secret pattern safety checks are enabled
        preferences = get_preferences()
        secret_pattern_safety_checks = preferences.get('secret_pattern_safety_checks', {})
        skip_secret_checks = not secret_pattern_safety_checks.get('enabled', False)
        
        # print_status(Colors.YELLOW, "Checking project safety for indexing...")
        # print(f"Project directory: {project_path.resolve()}")
        
        # Use the standalone parameter passed to the method
        is_standalone = standalone
        
        if is_standalone:
            print(' ')
            print_status(Colors.BLUE, "Checking project safety for indexing..")
            print_status(Colors.GRAY, f"Project directory: {project_path.resolve()}")
            print(' ')
        
        if self.exclusion_patterns and is_standalone:
            print_status(Colors.GRAY, f"* Excluding {len(self.exclusion_patterns)} patterns from security checks")
            for pattern in self.exclusion_patterns:
                print_status(Colors.GRAY, f"  - {pattern}")
        
        results = {
            'exact_matches': [],
            'pattern_matches': [],
            'secret_indicators': [],
            'suspicious_contents': []  # Will contain tuples of (file_path, pattern, line_num)
        }
        
        # Check exact matches
        results['exact_matches'] = self.check_exact_matches(project_path)
        if is_standalone:
            for pattern, file_path in results['exact_matches']:
                print_status(Colors.RED, f"❌ [Security] Found: {pattern} ({file_path})")
        
        # Check pattern matches
        results['pattern_matches'] = self.check_pattern_matches(project_path)
        if is_standalone:
            for pattern, file_path in results['pattern_matches']:
                print_status(Colors.RED, f"❌ [Security] Found files/directories containing: {pattern} ({file_path})")
        
        # Check secret indicators (skip if secret pattern safety checks are disabled)
        if not skip_secret_checks:
            results['secret_indicators'] = self.check_secret_indicators(project_path)
            if is_standalone:
                for indicator, file_path in results['secret_indicators']:
                    print_status(Colors.RED, f"⚠️  [Security] Potential secret indicator: {indicator} ({file_path})")
        else:
            results['secret_indicators'] = []
            if is_standalone:
                print_status(Colors.GRAY, "Skipping secret indicators check (disabled in preferences)")
        
        # Check file contents (skip if secret pattern safety checks are disabled)
        if not skip_secret_checks:
            results['suspicious_contents'] = self.check_file_contents(project_path)
            if is_standalone:
                for file_path, finding_type, line_num in results['suspicious_contents']:
                    print_status(Colors.RED, f"🔍 [Security] Potential secret detected ({finding_type}) in: {file_path} (line {line_num})")
        else:
            results['suspicious_contents'] = []
            if is_standalone:
                print_status(Colors.GRAY, "Skipping suspicious contents check (disabled in preferences)")
        
        # Determine if project is safe (only consider secret checks if enabled)
        if skip_secret_checks:
            is_safe = (len(results['exact_matches']) == 0 and 
                      len(results['pattern_matches']) == 0)
        else:
            is_safe = (len(results['exact_matches']) == 0 and 
                      len(results['pattern_matches']) == 0 and
                      len(results['suspicious_contents']) == 0)
        
        if is_standalone:
            if is_safe:
                if skip_secret_checks:
                    print_status(Colors.GREEN, "• No exposed secrets detected (secret pattern checks disabled). Proceeding..")
                else:
                    print_status(Colors.GREEN, "• No exposed secrets detected. Proceeding..")
            else:
                print_status(Colors.RED, "🚨 [Security] Project is not safe for indexing. Aborting..")
                print_status(Colors.RED, "Found sensitive information in files/directories that should be excluded. If secrets have been indexed or read by an AI, you should consider removing them from the project, invalidating them and renewing them. Opening an AI session without interacting is sufficient to index secrets. Secrets must not be stored in the project itself. Production secrets should be stored in a secure vault, unreadable by AI.  You may reference secrets from a different directory or vault (e.g. doppler, hashicorp vault, unix pass). If this path is a false positive, you shall add it to the '.claude/.exclude_security_checks' file.")
                
                if not skip_secret_checks and results['secret_indicators']:
                    print_status(Colors.YELLOW, "[Security] Note: Additional potential secret indicators found")
                if not skip_secret_checks and results['suspicious_contents']:
                    print_status(Colors.YELLOW, "[Security] Note: Files with potential secrets detected")
        
        return is_safe, results


def main():
    """Main function to handle command line arguments and run the safety check."""
    parser = argparse.ArgumentParser(
        description="Check if a project directory is safe for indexing by looking for sensitive files/directories.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # Check current directory
  %(prog)s /path/to/project   # Check specific directory
  %(prog)s -v                 # Verbose mode with content checking
        """
    )
    
    parser.add_argument(
        'project_directory',
        nargs='?',
        default='.',
        help='Directory to check (default: current directory)'
    )
    
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose mode (checks file contents and pattern matches)'
    )
    
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )
    
    parser.add_argument(
        '--standalone',
        action='store_true',
        help='Run in standalone mode with colored output'
    )
    
    args = parser.parse_args()
    
    try:
        project_path = Path(args.project_directory)
        checker = ProjectSafetyChecker()
        is_safe, results = checker.check_project_safety(project_path, standalone=args.standalone)
        
        # Check if running as a hook vs standalone
        is_hook = not args.standalone
        
        if is_hook:
            # JSON format for hooks
            if is_safe:
                output = {
                    "reason": "No exposed secrets detected. Proceeding."
                }
            else:
                # Prepare detailed findings without exposing secrets
                findings = []
                
                # Add exact matches
                for pattern, file_path in results['exact_matches']:
                    findings.append({
                        "type": "exact_match",
                        "pattern": pattern,
                        "file": file_path,
                        "line": None
                    })
                
                # Add pattern matches
                for pattern, file_path in results['pattern_matches']:
                    findings.append({
                        "type": "pattern_match",
                        "pattern": pattern,
                        "file": file_path,
                        "line": None
                    })
                
                # Add secret indicators
                for indicator, file_path in results['secret_indicators']:
                    findings.append({
                        "type": "secret_indicator",
                        "pattern": indicator,
                        "file": file_path,
                        "line": None
                    })
                
                # Add suspicious contents
                for file_path, finding_type, line_num in results['suspicious_contents']:
                    findings.append({
                        "type": "suspicious_content",
                        "pattern": finding_type,
                        "file": file_path,
                        "line": line_num
                    })
                
                # Convert findings to stringified tuples
                findings_strings = []
                for finding in findings:
                    if finding["line"] is not None:
                        findings_strings.append(f"(type: {finding['type']}, pattern: {finding['pattern']}, file: {finding['file']}, line: {finding['line']})")
                    else:
                        findings_strings.append(f"(type: {finding['type']}, pattern: {finding['pattern']}, file: {finding['file']})")
                
                findings_str = ", ".join(findings_strings)
                
                output = {
                    "continue": False,
                    "stopReason": f"Security policy violation. Project is not safe for indexing. Found potential secrets in files/directories that should be excluded: {findings_str}. If secrets have been indexed or read by an AI, you should consider invalidating them and renewing them. Opening an AI session without interacting is sufficient to index secrets. Secrets must not be stored in the project itself. Production secrets should be stored in a secure vault, unreadable by AI. You may reference secrets from a different directory or vault (e.g. doppler, hashicorp vault, unix pass). If this path is a false positive, you shall add it to the '.claude/.exclude_security_checks' file.",
                    "suppressOutput": True,
                    "decision": "block",
                    "reason": f"Security policy violation. Project is not safe for indexing. Found potential secrets in files/directories that should be excluded: {findings_str}. If secrets have been indexed or read by an AI, you should consider invalidating them and renewing them. Opening an AI session without interacting is sufficient to index secrets. Secrets must not be stored in the project itself. Production secrets should be stored in a secure vault, unreadable by AI. You may reference secrets from a different directory or vault (e.g. doppler, hashicorp vault, unix pass). If this path is a false positive, you shall add it to the '.claude/.exclude_security_checks' file."
                }
                log_decision(output, operation_type="prevent_learning_secrets_decision")
            print(json.dumps(output))
            
        elif args.json:
            # Convert tuples to dictionaries for JSON serialization
            json_results = results.copy()
            
            # Convert exact_matches tuples
            json_results['exact_matches'] = [
                {'pattern': pattern, 'file': file_path}
                for pattern, file_path in results['exact_matches']
            ]
            
            # Convert pattern_matches tuples
            json_results['pattern_matches'] = [
                {'pattern': pattern, 'file': file_path}
                for pattern, file_path in results['pattern_matches']
            ]
            
            # Convert secret_indicators tuples
            json_results['secret_indicators'] = [
                {'indicator': indicator, 'file': file_path}
                for indicator, file_path in results['secret_indicators']
            ]
            
            # Convert suspicious_contents tuples
            json_results['suspicious_contents'] = [
                {'file': file_path, 'finding_type': finding_type, 'line': line_num, 'severity': 'high'}
                for file_path, finding_type, line_num in results['suspicious_contents']
            ]
            
            print(' ')
            print('\033[90m* Debug information: \033[0m')
            output = {
                'safe': is_safe,
                'project_directory': str(project_path.resolve()),
                'results': json_results
            }
            print('\033[90m' + json.dumps(output, indent=2) + '\033[0m')
            print(' ')
        
        sys.exit(0 if is_safe else 2)
        
    except (FileNotFoundError, NotADirectoryError) as e:
        output = {
            "decision": "block",
            "reason": f"Error: {e}"
        }
        print(json.dumps(output))
        sys.exit(1)
    except KeyboardInterrupt:
        output = {
            "decision": "block",
            "reason": "Operation cancelled by user"
        }
        print(json.dumps(output))
        sys.exit(1)
    except Exception as e:
        output = {
            "decision": "block",
            "reason": f"Unexpected error: {e}"
        }
        print(json.dumps(output))
        sys.exit(1)


if __name__ == "__main__":
    main()
