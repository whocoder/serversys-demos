<?php

$DemoLoc = __DIR__.'/../../sourcetv';

function Demos_SectionRetrieved($section){
	global $Sys;

	if($section == 'demo-list'){
		$Demos = [];
		$Sys->Main->register_template('demo-list', __DIR__ . '/../sys-templates/demo-list.php');
		$Sys->Main->load_template('demo-list');
	}else if($section == 'demo-export'){
		$Server = $_GET['s'];
		$Demo = $_GET['d'];
		$Down = isset($_GET['confirmed']);

		if((!isset($Server)) || (!is_numeric($Server)))
			$Error = 'Invalid server specifier.';

		if((!isset($Demo)) || (!is_numeric($Demo)))
			$Error = 'Invalid demo specifier.';

		if(isset($Error)){
			$Sys->Main->register_template('error', __DIR__ . '/../sys-templates/error.php');

			$Sys->Main->Data['Error'] = $Error;
			$Sys->Main->load_template('error');

			die();
		}

		$query = $Sys->Database->prepare('SELECT demos.id, mid, timestamp, maps.name, game, timestamp_end, servers.name FROM demos, maps, servers WHERE demos.timestamp = ? AND demos.sid = ? AND servers.id = demos.sid AND maps.id = demos.mid;');
		$query->execute(array($Demo, $Server));
		$data = $query->fetchAll()[0];

		if($Down == true){
			$Sys->Main->register_template('demo-export', __DIR__ . '/../sys-templates/demo-export.php');
			$Sys->Main->load_template('demo-export');
		}else{
			var_dump($data);
			$Sys->Main->Data['Demo'] = [];
			$Sys->Main->Data['Demo']['ServerID'] = $Server;
			$Sys->Main->Data['Demo']['ServerName'] = $data[6];

			$Sys->Main->Data['Demo']['ID'] = $data[0];
			$Sys->Main->Data['Demo']['Timestamp'] = $data[2];
			$Sys->Main->Data['Demo']['TimestampEnd'] = $data[5];

			$Sys->Main->Data['Demo']['MapID'] = $data[1];
			$Sys->Main->Data['Demo']['MapName'] = $data[3];

			$Sys->Main->Data['Demo']['Game'] = $data[4];

			$Sys->Main->register_template('demo-export-confirm', __DIR__ . '/../sys-templates/demo-export-confirm.php');
			$Sys->Main->load_template('demo-export-confirm');
		}
	}
}

$Handler->register_hook('section_retrieved', 'Demos_SectionRetrieved');
