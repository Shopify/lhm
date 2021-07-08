CREATE TABLE `composite_primary_key_dest` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `shop_id` bigint(20) NOT NULL,
  CONSTRAINT `pk_composite` PRIMARY KEY (`shop_id`,`id`),
  INDEX `index_key_id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8
