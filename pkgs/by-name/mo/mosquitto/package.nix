{
  stdenv,
  lib,
  fetchFromGitHub,
  cmake,
  docbook_xsl,
  libxslt,
  cunit,
  gtest,
  c-ares,
  cjson,
  libargon2,
  libuuid,
  libuv,
  libwebsockets,
  openssl,
  python3,
  python3Packages,
  withSystemd ? lib.meta.availableOn stdenv.hostPlatform systemd,
  sqlite,
  systemd,
  uthash,
  nixosTests,
}:

let
  # Mosquitto needs external poll enabled in libwebsockets.
  libwebsockets' =
    (libwebsockets.override {
      withExternalPoll = true;
    }).overrideAttrs
      (old: {
        # Avoid bug in firefox preventing websockets being created over http/2 connections
        # https://github.com/eclipse/mosquitto/issues/1211#issuecomment-958137569
        cmakeFlags = old.cmakeFlags ++ [ "-DLWS_WITH_HTTP2=OFF" ];
      });

in
stdenv.mkDerivation (finalAttrs: {
  pname = "mosquitto";
  version = "2.1.2";
  doCheck = true; # upstream tests require

  src = fetchFromGitHub {
    owner = "eclipse-mosquitto";
    repo = "mosquitto";
    rev = "v${finalAttrs.version}";
    hash = "sha256-Zl55yjuzQY2fyaKs/zLaJ7a3OONKTDQPaT+DpPURdZI=";
  };

prePatch = ''
  echo "=== checking test files ==="
  ls -R test/apps || true
    ls -l test/apps/ctrl/ctrl-args.py || true
  head -n10 test/apps/ctrl/ctrl-args.py || true
  pwd
  command -v python3 || true
  command -v env || true
'';
checkPhase = ''
  runHook preCheck
  echo test-override
  ctest --output-on-failure --verbose  -j1
  runHook postCheck
'';
  postPatch = ''
    for f in html manpage ; do
      substituteInPlace man/$f.xsl \
        --replace http://docbook.sourceforge.net/release/xsl/current ${docbook_xsl}/share/xml/docbook-xsl
    done

    patchShebangs test


    substituteInPlace test/apps/passwd/passwd-changes.py \
      --replace-fail 'except PermissionError:' \
                     'except OSError:'
    substituteInPlace test/apps/ctrl/ctrl-dynsec.py \
      --replace-fail 'except PermissionError:' \
                     'except OSError:'
  substituteInPlace test/apps/signal/signal-args.py \
    --replace-fail 'do_test(["-p", "1", "config-reload"], 0)
do_test(["-p", "1", "log-rotate"], 0)
do_test(["-p", "1", "shutdown"], 0)
do_test(["-p", "1", "tree-print"], 0)
do_test(["-p", "1", "xtreport"], 0)
do_test(["-a", "config-reload"], 0)
' \'\'

  '';

  outputs = [
    "out"
    "dev"
    "lib"
  ];

  nativeBuildInputs = [
    cmake
    docbook_xsl
    libxslt
  ] ++ lib.optionals finalAttrs.doCheck [
    cunit
    gtest
    python3
    python3Packages.psutil
  ];

  buildInputs = [
    c-ares
    cjson
    libargon2
    libuuid
    libuv
    libwebsockets'
    openssl
    sqlite
    uthash
  ]
  ++ lib.optional withSystemd systemd;

  cmakeFlags = [
    (lib.cmakeBool "WITH_BUNDLED_DEPS" false)
    (lib.cmakeBool "WITH_WEBSOCKETS" true)
    (lib.cmakeBool "WITH_SYSTEMD" withSystemd)
    (lib.cmakeBool "WITH_TESTS" finalAttrs.doCheck)
  ];

  postFixup = ''
    sed -i "s|^libdir=.*|libdir=$lib/lib|g" $dev/lib/pkgconfig/*.pc
  '';

  passthru.tests = {
    inherit (nixosTests) mosquitto;
  };

  meta = {
    description = "Open source MQTT v3.1/3.1.1/5.0 broker";
    homepage = "https://mosquitto.org/";
    changelog = "https://github.com/eclipse/mosquitto/blob/v${finalAttrs.version}/ChangeLog.txt";
    license = lib.licenses.epl10;
    maintainers = with lib.maintainers; [
      peterhoeg
      sikmir
    ];
    platforms = lib.platforms.unix;
    mainProgram = "mosquitto";
  };
})
