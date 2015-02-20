Name:    adblock2privoxy
Version: 1.3.3
Release: 1%{?dist}
Summary: Convert adblock config files to privoxy format

License: GPL-3
URL:     https://projects.zubr.me/wiki/adblock2privoxy
Source0: http://hackage.haskell.org/package/adblock2privoxy-1.3.3/adblock2privoxy-1.3.3.tar.gz
Vendor:  Alexey Zubritskiy <adblock2privoxy@zubr.me>
Group:   Web

BuildRequires:  ghc-Cabal-devel
BuildRequires:  ghc-rpm-macros
BuildRequires:  cabal-install
BuildRequires:  zlib-devel

%description
AdBlock Plus browser plugin has great block list files provided by big community,
but it is client software and cannot work on a server as proxy.

Privoxy proxy has good potential to block ads at server side,
but it experiences acute shortage of updated block lists.

This software converts adblock lists to privoxy config files format.

Almost all adblock features are supported including

* block/unblock requests (on privoxy)

all syntax features are supported except for regex templates matching host name

* hide/unhide page elements (via CSS)

all syntax features are supported

* all block request options except for outdated ones:

Supported: script, image, stylesheet, object, xmlhttprequest, object-subrequest, subdocument,
document, elemhide, other, popup, third-party, domain=..., match-case, donottrack

Unsupported: collapse, background, xbl, ping and dtd


%prep
%setup -q -T -D -n root
cabal update
cabal install --user --only-dependencies --enable-optimization=2


%build
%global cabal_configure_options --user
%global ghc_user_conf 1
%global ghc_without_dynamic 1
%ghc_bin_build


%install
%ghc_bin_install
cp -r man %{buildroot}%{_mandir}


%files
%doc %{_mandir}
%doc LICENSE README.rst INSTALL.rst changelog
%{_bindir}/%{name}
%{_datadir}/%{name}-%{version}


%changelog
* Fri Feb 20 2015 Alexey Zubritskiy <adblock2privoxy@zubr.me> - 1.3.3
- Rpm release for new version (generated from cabal file)
