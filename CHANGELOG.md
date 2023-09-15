# Unreleased

# 4.0.0 (Sep, 2023)
* Deprecate `SlaveLag` throttler class name. Use `ReplicaLag` instead (https://github.com/Shopify/lhm/pull/144)
* Deprecate `slave_lag_throttler` throttler config value. Use `replica_lag_throttler` instead (https://github.com/Shopify/lhm/pull/144)
* Fix errors when creating indexes with whitespace between column names and sizes. (https://github.com/Shopify/lhm/pull/145)
* Test against Ruby 3.2 and Rails 7.1.0.beta1. (https://github.com/Shopify/lhm/pull/146)
* Drop support for Ruby 2 and Rails 5. (https://github.com/Shopify/lhm/pull/148)
* Fix thread throttler #stride API. (https://github.com/Shopify/lhm/pull/131)

# 3.5.5 (Jan, 2022)
* Fix error where from Config shadowing which would cause LHM to abort on reconnect (https://github.com/Shopify/lhm/pull/128)

# 3.5.4 (Dec, 2021)
* Refactored the way options are handled internally. Code is now much clearer to understand
* Removed optional connection_options from `Lhm.setup` and `Lhm.connection`
* Option `reconnect_with_consistent_host` will now be provided with `options` for `Lhm.change_table`

# 3.5.3 (Dec, 2021)
* Adds ProxySQL comments at the end of query to accommodate for internal tool's requirements

# 3.5.2 (Dec, 2021)
* Fixed error on undefined connection, when calling `Lhm.connection` without calling `Lhm.setup` first
* Changed `Lhm.connection.connection` to `lhm.connection.ar_connection` for increased clarity and readability

# 3.5.1 (Dec , 2021)
* Add better logging to the LHM components (https://github.com/Shopify/lhm/pull/112)
* Slave lag throttler now supports ActiveRecord > 6.0
* [Dev] Add `Appraisals` to test against multiple version

# 3.5.0 (Dec , 2021)
* Duplicate of 3.4.2 (unfortunate mistake)

# 3.4.2 (Sept, 2021)
* Fixed Chunker's undefined name error (https://github.com/Shopify/lhm/pull/110)

# 3.4.1 (Sep 22, 2021)

* Add better logging to the LHM components (https://github.com/Shopify/lhm/pull/108)

# 3.4.0 (Jul 19, 2021)

* Log or raise on unexpected duplicated entry warnings during INSERT IGNORE (https://github.com/Shopify/lhm/pull/100)

# 3.3.6 (Jul 7, 2021)

* Add lhm-shopify.rb to require lhm

# 3.3.5 (Jul 5, 2021)

* Add comment and collate copying to rename_column
* Publish to rubygems

# 3.3.4 (Feb 9, 2021)

* Run migrations inline in local/CI environment

# 3.3.3 (Nov 20, 2020)

* Add test for tables with composite primary keys.
* Add test for migrating to a composite primary key.
* Tests updated to work on MacOS Catalina
* LHM will now print exceptions to @printer if @printer responds to :exception
* New ThreadsRunning throttler uses MySQL Performance Schema to decide whether to throttle

# 3.3.2 (not fully released)

* Catch _even_ more MySQL errors by default with SqlRetry.

# 3.3.1 (Nov 8, 2019)

* Ensure that :retriable configuration is correctly passed to all SqlRetry
  instances.
* Retry `Chunker#upper_id` and `options[:verifier]` on MySQL failure.
* Catch more MySQL errors by default with SqlRetry.

# 3.3.0 (Oct 21, 2019)

* Add a :verifier key to the options hash, with a default implementation which aborts the LHM if the triggers are removed.

# 3.2.5 (Jun 24, 2019)

* Tighten dependency on retriable gem and remove workarounds for old version

# 3.2.4 (Oct 16, 2018)

* Retry `Cleanup::Current` just like we retry all the other DDLs.

# 3.2.3 (Oct 16, 2018)

* Add ActiveRecord::QueryTimedout exception class to be retried on "Timeout waiting for a response from the last query" message.

# 3.2.2 (Oct 11, 2018)

* Try to take a higher lock_wait_timeout value than others  (https://github.com/Shopify/lhm/pull/60)

# 3.2.1 (Oct 11, 2018)

* Retry on `MySQL::Error::Timeout` (https://github.com/Shopify/lhm/pull/57)
* Retry 20 times by default (https://github.com/Shopify/lhm/pull/58)

# 3.2.0 (Sep 4, 2018)

* Fix Slave lag throttler database config (https://github.com/Shopify/lhm/pull/55)
* Loosen dependency on retriable gem (https://github.com/Shopify/lhm/pull/54)
* Overhaul retries for deadlocks, wait timeouts on Chunker, Entangler, and AtomicSwitcher (https://github.com/Shopify/lhm/pull/51)

# 3.1.1

* Cleanup tables between tests (https://github.com/Shopify/lhm/pull/48)
* Ensure all table names are less than 64 characters (https://github.com/Shopify/lhm/pull/49)

# 3.1.0

* Unify Entangler and AtomicSwitcher retry interface (https://github.com/Shopify/lhm/pull/39)
* Remove scripts replaced by dbdeployer (https://github.com/Shopify/lhm/pull/40)
* Rename lhmn_ tables to lhma_ to avoid IBP stalls (https://github.com/Shopify/lhm/pull/41)

# 3.0.0

* Drop support for throttle and stride options. Use `throttler`, instead:
```
Lhm.change_table :users, throttler: [:time_throttler, {stride: x}] do
end
```
* #118 - Truncate long trigger names. (@sj26)
* #114 - Update chunker requirements (@bjk-soundcloud)
* #98 - Add slave lag throttler. (@camilo, @jasonhl)
* #92 - Fix check for table requirement before starting a lhm.(@hannestyden)
* #93 - Makes the atomic switcher retry on metadata locks (@camilo)
* #63 - Sets the LHM's session lock wait timeout variables (@camilo)
* #75 - Remove DataMapper and ActiveRecord 2.x support (@camilo)

# 2.2.0 (Jan 16, 2015)

* #84 - Require index names to be strings or symbols (Thibaut)
* #39 - Adding the ability to rename columns (erikogan)
* #67 - Allow for optional time filter on .cleanup (joelr)

# 2.1.0 (July 31, 2014)

* #48 - Add percentage output for migrations (@arthurnn)
* #60 - Quote table names (@spickermann)
* #59 - Escape table name in select_limit and select_start methods (@stevehodgkiss)
* #57 - Ensure chunking 'where' clause handled separately (@rentalcustard)
* #54 - Chunker handle stride changes (@rentalcustard)
* #52 - Implement ability to control timeout and stride from Throttler (@edmundsalvacion)
* #51 - Ensure Lhm.cleanup removes temporary triggers (@edmundsalvacion)
* #46 - Allow custom throttler (@arthurnn)

# 2.0.0 (July 10, 2013)

* #44 - Conditional migrations (@durran)

# 1.3.0 (May 28, 2013)

* Add Lhm.cleanup method for removing copy tables, thanks @bogdan
* Limit copy table names to 64 characters, thanks @charliesome

# 1.2.0 (February 22, 2013)

* Added DataMapper support, no API changes for current users. Refer to the
  README for information.
* Documentation updates. Thanks @tiegz and @vinbarnes.

# 1.1.0 (April 29, 2012)

* Add option to specify custom index name
* Add mysql2 compatibility
* Add AtomicSwitcher

# 1.0.3 (February 23, 2012)

* Improve change_column

# 1.0.2 (February 17, 2012)

* closes https://github.com/soundcloud/large-hadron-migrator/issues/11
  this critical bug could cause data loss. table parser was replaced with
  an implementation that reads directly from information_schema.

# 1.0.1 (February 09, 2012)

* released to rubygems

# 1.0.0 (February 09, 2012)

* added change_column
* final 1.0 release

# 1.0.0.rc8 (February 09, 2012)

* removed spec binaries from gem bins

# 1.0.0.rc7 (January 31, 2012)

* added SqlHelper.annotation into the middle of trigger statements. this
  is for the benefit of the killer script which should not kill trigger
  statements.

# 1.0.0.rc6 (January 30, 2012)

* added --confirm to kill script; fixes to kill script

# 1.0.0.rc5 (January 30, 2012)

* moved scripts into bin, renamed, added to gem binaries

# 1.0.0.rc4 (January 29, 2012)

* added '-- lhm' to the end of statements for more visibility

# 1.0.0.rc3 (January 19, 2012)

* Speedup migrations for tables with large minimum id
* Add a bit yard documentation
* Fix issues with index creation on reserved column names
* Improve error handling
* Add tests for replication
* Rename public API method from `hadron_change_table` to `change_table`
* Add tests for ActiveRecord 2.3 and 3.1 compatibility

# 1.0.0.rc2 (January 18, 2012)

* Speedup migrations for tables with large ids
* Fix conversion of milliseconds to seconds
* Fix handling of sql errors
* Add helper to create unique index
* Allow index creation on prefix of column
* Quote column names on index creation
* Remove ambiguous method signature
* Documentation fix
* 1.8.7 compatibility

# 1.0.0.rc1 (January 15, 2012)

* rewrite.

# 0.2.1 (November 26, 2011)

* Include changelog in gem

# 0.2.0 (November 26, 2011)

* Add Ruby 1.8 compatibility
* Setup travis continuous integration
* Fix record lose issue
* Fix and speed up specs

# 0.1.4

* Merged [Pullrequest #9](https://github.com/soundcloud/large-hadron-migrator/pull/9)

# 0.1.3

* code cleanup
* Merged [Pullrequest #8](https://github.com/soundcloud/large-hadron-migrator/pull/8)
* Merged [Pullrequest #7](https://github.com/soundcloud/large-hadron-migrator/pull/7)
* Merged [Pullrequest #4](https://github.com/soundcloud/large-hadron-migrator/pull/4)
* Merged [Pullrequest #1](https://github.com/soundcloud/large-hadron-migrator/pull/1)

# 0.1.2

* Initial Release
