import 'dart:io';

import 'package:process_run/shell.dart';
import 'package:reboot_launcher/cli.dart';

import '../model/fortnite_version.dart';
import '../util/injector.dart';
import '../util/os.dart';
import '../util/process.dart';
import '../util/server.dart';

final List<String> _errorStrings = [
  "port 3551 failed: Connection refused",
  "Unable to login to Fortnite servers",
  "HTTP 400 response from ",
  "Network failure when attempting to check platform restrictions",
  "UOnlineAccountCommon::ForceLogout"
];

Process? _gameProcess;
Process? _launcherProcess;
Process? _eacProcess;

Future<void> startGame() async {
  await _startLauncherProcess(version);
  await _startEacProcess(version);

  var gamePath = version.executable?.path;
  if (gamePath == null) {
    throw Exception("${version.location
        .path} no longer contains a Fortnite executable, did you delete or move it?");
  }

  if (username == null) {
    username = "Reboot${host ? 'Host' : 'Player'}";
    stdout.writeln("No username was specified, using $username by default. Use --username to specify one");
  }

  _gameProcess = await Process.start(gamePath, createRebootArgs(username!, "", host, ""))
    ..exitCode.then((_) => _onClose())
    ..outLines.forEach((line) => _onGameOutput(line, dll, host, verbose));
}


Future<void> _startLauncherProcess(FortniteVersion dummyVersion) async {
  if (dummyVersion.launcher == null) {
    return;
  }

  _launcherProcess = await Process.start(dummyVersion.launcher!.path, []);
  suspend(_launcherProcess!.pid);
}

Future<void> _startEacProcess(FortniteVersion dummyVersion) async {
  if (dummyVersion.eacExecutable == null) {
    return;
  }

  _eacProcess = await Process.start(dummyVersion.eacExecutable!.path, []);
  suspend(_eacProcess!.pid);
}

void _onGameOutput(String line, String dll, bool hosting, bool verbose) {
  if(verbose) {
    stdout.writeln(line);
  }

  if(line.contains("Platform has ")){
    _injectOrShowError("cobalt.dll");
    return;
  }

  if (line.contains("FOnlineSubsystemGoogleCommon::Shutdown()")) {
    _onClose();
    return;
  }

  if(_errorStrings.any((element) => line.contains(element))){
    stderr.writeln("The backend doesn't work! Token expired");
    _onClose();
    return;
  }

  if(line.contains("Region ")){
    if(hosting) {
      _injectOrShowError(dll, false);
    }else {
      _injectOrShowError("console.dll");
    }

    _injectOrShowError("memoryleak.dll");
  }
}

void _kill() {
  _gameProcess?.kill(ProcessSignal.sigabrt);
  _launcherProcess?.kill(ProcessSignal.sigabrt);
  _eacProcess?.kill(ProcessSignal.sigabrt);
}

Future<void> _injectOrShowError(String binary, [bool locate = true]) async {
  if (_gameProcess == null) {
    return;
  }

  try {
    stdout.writeln("Injecting $binary...");
    var dll = locate ? File("${assetsDirectory.path}\\dlls\\$binary") : File(binary);
    if(!dll.existsSync()){
      throw Exception("Cannot inject $dll: missing file");
    }

    await injectDll(_gameProcess!.pid, dll.path);
  } catch (exception) {
    throw Exception("Cannot inject binary: $binary");
  }
}

void _onClose() {
  _kill();
  sleep(const Duration(seconds: 3));
  stdout.writeln("The game was closed");
  if(autoRestart){
    stdout.writeln("Restarting automatically game");
    startGame();
    return;
  }

  exit(0);
}