# CHANGELOG

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
