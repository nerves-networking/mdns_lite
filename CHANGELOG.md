# CHANGELOG

## v0.7.0

* Breaking change
  * Change optional dependency on VintageNet to a mandatory one. Probably all
    `:mdns_lite` users were already using VintageNet and since Mix releases
    doesn't support optional dependencies yet, some users got errors when the
    release misordered them. This avoids the problem.

* Improvements
  * Removed the `:dns` package dependency. There as an Erlang crypto API call in
    a dependency of `:dns` that was removed in OTP 24. This change makes it
    possible to use `:mdns_lite` on OTP 24 without worrying about a missing
    crypto API call.

## v0.6.7

* Improvements
  * Exclude `"wwan0"` by default. These interfaces are cellular links like ppp
    and it's not appropriate to respond to mDNS on them either.

## v0.6.6

* Bug fixes
  * Advertise services based on service names & not hostname. Thanks to Matt
    Trudel for this fix.

## v0.6.5

* Bug fixes
  * Reuse addresses and ports when binding to the multicast socket to coexist
    with other mDNS software. Thanks to Eduardo Cunha and Matt Myers for the
    updates.

## v0.6.4

* New features
  * Support custom TXT record contents. See the `:txt_payload`. Thanks to
    Eduardo Cunha for adding this.

## v0.6.3

* Bug fixes
  * Update default so that ppp interfaces are ignored. This prevents surprises
    of having a responder run on a cellular link.

## v0.6.2

* Bug fixes
  * Fix crash when handling undecodable mDNS messages

## v0.6.1

* Handle nil from VintageNet reports

## v0.6.0

* Allow mdns host to be change at runtime
* New network monitor: VintageNetMonitor

## v0.5.0

* Allow services to be added and removed at runtime.

## v0.4.3

* Correct typos and white space
* Comment out logger messages

## v0.4.2

* Remove un-helpful Logger.debug statements - Issue #49
* Put this file into the proper order.

## v0.4.1

* Correct bad tag in README.md and correct grammar.
* Correct documentation of the MdnsLite module

## v0.4.0

* The value of host in the configuration file can have two values. The second can serve as an alias for the first.
* Updated documentation and comments.
* Created a new test.

## v0.3.0

* Remove a superfluous map from the config.

## v0.2.1

* Update README to reflect changes in previous version.

## v0.2.0

* Much better alignment with RFC 6763 - DNS Service-based discovery.
* Affects handling of SRV and PTR queries.

## v0.1.0

* Initial release
