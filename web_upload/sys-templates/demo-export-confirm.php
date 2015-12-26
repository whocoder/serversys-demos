<html lang="en">
	<?php $Sys->Main->load_template('head'); ?>

	<?php $Sys->Main->load_template('header'); ?>

	<div class="container">
		<div class="row">
			<h1><?= $Sys->Main->Lang['demo-export-title'] ?></h1>
			<hr />
			<p>

				<?= $Sys->Main->Lang['demo-export-description'] ?>

			</p>
			<a class="btn btn-default btn-md" href="?section=demo-export&<?= 's=' . $Sys->Main->Data['Demo']['ServerID'] . '&d=' . $Sys->Main->Data['Demo']['Timestamp'] ?>&confirmed=1"><?= $Sys->Main->Lang['download'] ?></a>
		</div>
	</div>

	<?php $Sys->Main->load_template('footer'); ?>

</html>
