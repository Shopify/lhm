CREATE TABLE `myisam_users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `reference` int(11) DEFAULT NULL,
  `username` varchar(255) DEFAULT NULL,
  `group` varchar(255) DEFAULT 'Superfriends',
  `created_at` datetime DEFAULT NULL,
  `comment` varchar(20) DEFAULT NULL,
  `description` text,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM CHARSET=utf8
