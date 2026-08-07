<?php

// ProcessMaker 3.8.3's PHP 8 cron launcher can use G::LoadTranslation()
// before defining this constant. Define the CLI fallback before cron.php loads.
if (!defined('SYS_LANG')) {
    define('SYS_LANG', 'en');
}

// A fresh installation has no .server_info until the first successful browser
// login, but scheduled-case cron needs it immediately. Seed only a missing
// file from explicit deployment settings; a later login remains free to
// replace it with ProcessMaker's full request-derived value.
$root = getenv('PROCESSMAKER_ROOT') ?: '/opt/processmaker';
$workspace = getenv('PM_WORKSPACE') ?: 'workflow';
$host = getenv('PM_PUBLIC_HOST') ?: 'localhost';
$port = getenv('PM_PUBLIC_PORT') ?: '8080';
$scheme = getenv('PM_PUBLIC_SCHEME') ?: ((string) $port === '443' ? 'https' : 'http');
$site = $root . '/shared/sites/' . $workspace;
$serverInfo = $site . '/.server_info';

$validWorkspace = preg_match('/^[A-Za-z0-9_-]+$/', $workspace) === 1;
$validHost = $host !== '' && strlen($host) <= 253 &&
    preg_match('#[\\s/]#', $host) !== 1;
$validPort = ctype_digit((string) $port) && (int) $port >= 1 &&
    (int) $port <= 65535;
$validScheme = in_array($scheme, ['http', 'https'], true);

if ($validWorkspace && $validHost && $validPort && $validScheme &&
    is_dir($site) && !is_file($serverInfo)) {
    $hostWithPort = $host . (in_array((int) $port, [80, 443], true) ? '' : ':' . $port);
    $server = [
        'SERVER_NAME' => $host,
        'SERVER_PORT' => (string) $port,
        'HTTP_HOST' => $hostWithPort,
        'REQUEST_SCHEME' => $scheme,
        'HTTPS' => $scheme === 'https' ? 'on' : 'off',
        'HTTP_X_FORWARDED_PROTO' => $scheme,
        'DOCUMENT_ROOT' => $root . '/workflow/public_html',
        'SCRIPT_FILENAME' => $root . '/workflow/public_html/app.php',
        'SCRIPT_NAME' => '/app.php',
        'REMOTE_ADDR' => '127.0.0.1',
    ];
    file_put_contents($serverInfo, serialize($server), LOCK_EX);
    @chmod($serverInfo, 0644);
}
