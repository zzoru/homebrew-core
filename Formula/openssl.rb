# This formula tracks 1.0.2 branch of OpenSSL, not the 1.1.0 branch. Due to
# significant breaking API changes in 1.1.0 other formulae will be migrated
# across slowly, so core will ship `openssl` & `openssl@1.1` for foreseeable.
class Openssl < Formula
  desc "SSL/TLS cryptography library"
  homepage "https://openssl.org/"
  url "https://www.openssl.org/source/openssl-1.0.2q.tar.gz"
  mirror "https://dl.bintray.com/homebrew/mirror/openssl--1.0.2q.tar.gz"
  mirror "https://www.mirrorservice.org/sites/ftp.openssl.org/source/openssl-1.0.2q.tar.gz"
  mirror "http://artfiles.org/openssl.org/source/openssl-1.0.2q.tar.gz"
  sha256 "5744cfcbcec2b1b48629f7354203bc1e5e9b5466998bbccc5b5fcde3b18eb684"
  revision 1 unless OS.mac?

  bottle do
    sha256 "c719259835b8d1ae7b0f627986a127fe4bb9bd161c03a86417b23e73a0878fe8" => :x86_64_linux
  end

  keg_only :provided_by_macos,
    "Apple has deprecated use of OpenSSL in favor of its own TLS and crypto libraries"

  # An updated list of CA certificates for use by Leopard, whose built-in certificates
  # are outdated, and Snow Leopard, whose `security` command returns no output.
  resource "ca-bundle" do
    url "https://curl.haxx.se/ca/cacert-2018-10-17.pem"
    mirror "http://gitcdn.xyz/cdn/paragonie/certainty/d3e2777e1ca2b1401329a49c7d56d112e6414f23/data/cacert-2018-10-17.pem"
    sha256 "86695b1be9225c3cf882d283f05c944e3aabbc1df6428a4424269a93e997dc65"
  end

  resource "cacert" do
    # homepage "http://curl.haxx.se/docs/caextract.html"
    url "https://curl.haxx.se/ca/cacert-2017-01-18.pem"
    mirror "http://cdn.rawgit.com/sjackman/e4066d2cb6b45fbb6d213e676cb109d0/raw/58964378cb5eefe96cba245ef863c57fb2b480e0/cacert-2017-01-18.pem"
    sha256 "e62a07e61e5870effa81b430e1900778943c228bd7da1259dd6a955ee2262b47"
  end unless OS.mac?

  # Use standard env on Snow Leopard to allow compilation fix below to work.
  env :std if MacOS.version == :snow_leopard

  def arch_args
    if OS.mac?
      %w[
        darwin64-x86_64-cc
        enable-ec_nistp_64_gcc_128
      ]
    else
      %w[linux-x86_64]
    end
  end

  def configure_args; %W[
    --prefix=#{prefix}
    --openssldir=#{openssldir}
    no-ssl2
    no-ssl3
    no-zlib
    shared
    enable-cms
    #{[ENV.cppflags, ENV.cflags, ENV.ldflags].join(" ").strip unless OS.mac?}
  ]
  end

  def install
    # openssl does not in fact require an executable stack.
    ENV.append_to_cflags "-Wa,--noexecstack" unless OS.mac?

    # OpenSSL will prefer the PERL environment variable if set over $PATH
    # which can cause some odd edge cases & isn't intended. Unset for safety,
    # along with perl modules in PERL5LIB.
    ENV.delete("PERL")
    ENV.delete("PERL5LIB")

    # Keep Leopard/Snow Leopard support alive for things like building portable Ruby by
    # avoiding a makedepend issue introduced in recent versions of OpenSSL 1.0.2.
    # https://github.com/Homebrew/homebrew-core/pull/34326
    depend_args = []
    depend_args << "MAKEDEPPROG=cc" if MacOS.version <= :snow_leopard

    # Build with GCC on Snow Leopard, which errors during tests if built with its clang.
    # https://github.com/Homebrew/homebrew-core/issues/2766
    args = []
    args << "CC=cc" if MacOS.version == :snow_leopard

    ENV.deparallelize
    system "perl", "./Configure", *(configure_args + arch_args), *("enable-md2" unless OS.mac?)
    system "make", "depend", *depend_args
    system "make", *args
    if which "cmp"
      system "make", "test"
    else
      opoo "Skipping `make check` due to unavailable `cmp`"
    end
    system "make", "install", "MANDIR=#{man}", "MANSUFFIX=ssl"
  end

  def openssldir
    etc/"openssl"
  end

  def post_install
    unless OS.mac?
      # Download and install cacert.pem from curl.haxx.se
      cacert = resource("cacert")
      rm_f openssldir/"cert.pem"
      filename = Pathname.new(cacert.url).basename
      openssldir.install cacert.files(filename => "cert.pem")
      return
    end

    keychains = %w[
      /System/Library/Keychains/SystemRootCertificates.keychain
    ]

    certs_list = `security find-certificate -a -p #{keychains.join(" ")}`
    certs = certs_list.scan(
      /-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m,
    )

    valid_certs = certs.select do |cert|
      IO.popen("#{bin}/openssl x509 -inform pem -checkend 0 -noout", "w") do |openssl_io|
        openssl_io.write(cert)
        openssl_io.close_write
      end

      $CHILD_STATUS.success?
    end

    openssldir.mkpath
    if MacOS.version <= :snow_leopard
      resource("ca-bundle").stage do
        openssldir.install "cacert-#{resource("ca-bundle").version}.pem" => "cert.pem"
      end
    else
      (openssldir/"cert.pem").atomic_write(valid_certs.join("\n") << "\n")
    end
  end

  def caveats; <<~EOS
    A CA file has been bootstrapped using certificates from the SystemRoots
    keychain. To add additional certificates (e.g. the certificates added in
    the System keychain), place .pem files in
      #{openssldir}/certs

    and run
      #{opt_bin}/c_rehash
  EOS
  end

  test do
    # Make sure the necessary .cnf file exists, otherwise OpenSSL gets moody.
    assert_predicate HOMEBREW_PREFIX/"etc/openssl/openssl.cnf", :exist?,
            "OpenSSL requires the .cnf file for some functionality"

    # Check OpenSSL itself functions as expected.
    (testpath/"testfile.txt").write("This is a test file")
    expected_checksum = "e2d0fe1585a63ec6009c8016ff8dda8b17719a637405a4e23c0ff81339148249"
    system "#{bin}/openssl", "dgst", "-sha256", "-out", "checksum.txt", "testfile.txt"
    open("checksum.txt") do |f|
      checksum = f.read(100).split("=").last.strip
      assert_equal checksum, expected_checksum
    end
  end
end
