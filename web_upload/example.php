<?php
	// Export demo example

	$Demo = null;
	$Error = null;

	$DemoPath = __DIR__ . '/../../demos';

	if(isset($_GET['demo']) && is_numeric($_GET['demo'])){
		$Demo = $DemoPath . '/' . $_GET['demo'] .'.dem';

		if(!file_exists($Demo)){
			$Error = 'This demo does not exist!';
		}
	}else{
		$Error = 'Please supply a demo ID (?demo=)';
	}

	if(!isset($Error) && isset($Demo)){
		header('Content-Description: File Transfer');
		header('Content-Type: application/octet-stream');
		header('Content-Disposition: attachment; filename="'.basename($Demo).'"');
		header('Expires: 0');
		header('Cache-Control: must-revalidate');
		header('Pragma: public');
		header('Content-Length: ' . filesize($Demo));

		readfile($Demo);
	}else{
		echo $Error;
	}

	die();
?>
