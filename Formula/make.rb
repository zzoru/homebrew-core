class Make < Formula
  desc "Utility for directing compilation"
  homepage "https://www.gnu.org/software/make/"
  url "https://ftp.gnu.org/gnu/make/make-4.2.1.tar.bz2"
  mirror "https://ftpmirror.gnu.org/make/make-4.2.1.tar.bz2"
  sha256 "d6e262bf3601b42d2b1e4ef8310029e1dcf20083c5446b4b7aa67081fdffc589"
  revision 1

  bottle do
    rebuild 2
    sha256 "77c4ba8e8b6d7ff0b8ea9b4cac2026882888196c2f39cdbdd004b92757a07ccf" => :mojave
    sha256 "9486542a6ad3207c3f7e00c80f99a562014d6fc8aa833036c3927d11a6cee0ee" => :high_sierra
    sha256 "8641015924620134cfa26c18eb665503950291d1110d72f876354242136cfa77" => :sierra
    sha256 "bf53022e4dc6cffdcf0feec6eef54a7ff8ebf58cda6dcb67fe951f68961c16d1" => :x86_64_linux
  end

  def install
    args = %W[
      --disable-dependency-tracking
      --prefix=#{prefix}
    ]

    args << "--program-prefix=g" if OS.mac?
    system "./configure", *args
    system "make", "install"

    if OS.mac?
      (libexec/"gnubin").install_symlink bin/"gmake" =>"make"
      (libexec/"gnuman/man1").install_symlink man1/"gmake.1" => "make.1"
    end
  end

  def caveats
    return unless OS.mac?
    <<~EOS
      GNU "make" has been installed as "gmake".
      If you need to use it as "make", you can add a "gnubin" directory
      to your PATH from your bashrc like:

          PATH="#{opt_libexec}/gnubin:$PATH"

      Additionally, you can access its man page with normal name if you add
      the "gnuman" directory to your MANPATH from your bashrc as well:

          MANPATH="#{opt_libexec}/gnuman:$MANPATH"
    EOS
  end

  test do
    (testpath/"Makefile").write <<~EOS
      default:
      \t@echo Homebrew
    EOS
    if OS.mac?
      assert_equal "Homebrew\n", shell_output("#{bin}/gmake")
      assert_equal "Homebrew\n", shell_output("#{opt_libexec}/gnubin/make")
    end

    unless OS.mac?
      assert_equal "Homebrew\n", shell_output("#{bin}/make")
    end
  end
end
