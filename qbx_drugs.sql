CREATE TABLE IF NOT EXISTS `dealers` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL DEFAULT '0',
  `coords` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `time` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `createdby` varchar(50) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dealer 1: Downtown Drug Dealer
INSERT INTO `dealers` (`name`, `coords`, `time`, `createdby`) VALUES
('Downtown_Dave', '{"x": 137.5, "y": -1705.2, "z": 29.3}', '{"min": 20, "max": 6}', 'admin');

-- Dealer 2: Vinewood Heights Dealer
INSERT INTO `dealers` (`name`, `coords`, `time`, `createdby`) VALUES
('Vinewood_Vic', '{"x": -306.8, "y": 6299.5, "z": 32.4}', '{"min": 18, "max": 4}', 'admin');

-- Dealer 3: Sandy Shores Dealer
INSERT INTO `dealers` (`name`, `coords`, `time`, `createdby`) VALUES
('Sandy_Sam', '{"x": 1962.3, "y": 3740.8, "z": 32.3}', '{"min": 21, "max": 5}', 'admin');

-- Dealer 4: Paleto Bay Dealer
INSERT INTO `dealers` (`name`, `coords`, `time`, `createdby`) VALUES
('Paleto_Pete', '{"x": -114.4, "y": 6450.2, "z": 31.5}', '{"min": 19, "max": 3}', 'admin');

-- Dealer 5: Mirror Park Dealer
INSERT INTO `dealers` (`name`, `coords`, `time`, `createdby`) VALUES
('Mirror_Mike', '{"x": 1234.5, "y": -678.9, "z": 66.4}', '{"min": 22, "max": 2}', 'admin');
