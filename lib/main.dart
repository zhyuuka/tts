import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'LarynxONNXTTS.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Larynx TTS',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Larynx TTS 离线语音合成'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // TTS引擎实例
  late LarynxONNXTTS _ttsEngine;
  // 文本控制器
  final TextEditingController _textController = TextEditingController();
  // 状态文本
  String _statusText = '请输入文本并点击合成';
  // 是否正在合成
  bool _isSynthesizing = false;
  // 语速
  double _speed = 1.0;
  // 音量
  double _volume = 1.0;
  // 合成的音频数据
  Uint8List? _audioData;
  // 播放状态
  bool _isPlaying = false;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    // 初始化TTS引擎
    _initializeTTS();
  }

  @override
  void dispose() {
    // 释放资源
    _ttsEngine.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// 初始化TTS引擎
  Future<void> _initializeTTS() async {
    try {
      setState(() {
        _statusText = '正在初始化TTS引擎...';
      });
      
      // 创建TTS引擎实例，使用assets中的模型文件
      _ttsEngine = LarynxONNXTTS('assets/models/model.onnx');
      await _ttsEngine.initialize();
      
      setState(() {
        _statusText = 'TTS引擎初始化成功，请输入文本并点击合成';
      });
    } catch (e) {
      setState(() {
        _statusText = 'TTS引擎初始化失败: $e';
      });
      print('TTS初始化失败: $e');
    }
  }

  /// 合成文本
  Future<void> _synthesizeText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _statusText = '请输入要合成的文本';
      });
      return;
    }

    try {
      setState(() {
        _isSynthesizing = true;
        _statusText = '正在合成语音...';
      });

      // 检查文本长度，长文本使用分段合成
      Uint8List audioData;
      if (text.length > 100) {
        audioData = await _ttsEngine.synthesizeLongText(text);
      } else {
        audioData = await _ttsEngine.synthesize(text);
      }

      setState(() {
        _audioData = audioData;
        _isSynthesizing = false;
        _statusText = '合成完成，点击播放按钮收听';
      });
    } catch (e) {
      setState(() {
        _isSynthesizing = false;
        _statusText = '合成失败: $e';
      });
      print('合成失败: $e');
    }
  }

  /// 播放音频
  Future<void> _playAudio() async {
    if (_audioData == null) {
      setState(() {
        _statusText = '请先合成语音';
      });
      return;
    }

    try {
      await _ttsEngine.play(_audioData!);
      setState(() {
        _isPlaying = true;
        _isPaused = false;
        _statusText = '正在播放...';
      });
    } catch (e) {
      setState(() {
        _statusText = '播放失败: $e';
      });
      print('播放失败: $e');
    }
  }

  /// 暂停播放
  Future<void> _pauseAudio() async {
    try {
      await _ttsEngine.pause();
      setState(() {
        _isPaused = true;
        _isPlaying = false;
        _statusText = '播放已暂停';
      });
    } catch (e) {
      setState(() {
        _statusText = '暂停失败: $e';
      });
      print('暂停失败: $e');
    }
  }

  /// 继续播放
  Future<void> _resumeAudio() async {
    try {
      await _ttsEngine.resume();
      setState(() {
        _isPlaying = true;
        _isPaused = false;
        _statusText = '正在播放...';
      });
    } catch (e) {
      setState(() {
        _statusText = '继续播放失败: $e';
      });
      print('继续播放失败: $e');
    }
  }

  /// 停止播放
  Future<void> _stopAudio() async {
    try {
      await _ttsEngine.stop();
      setState(() {
        _isPlaying = false;
        _isPaused = false;
        _statusText = '播放已停止';
      });
    } catch (e) {
      setState(() {
        _statusText = '停止失败: $e';
      });
      print('停止失败: $e');
    }
  }

  /// 更新语速
  void _updateSpeed(double value) {
    setState(() {
      _speed = value;
      _ttsEngine.setSpeed(value);
    });
  }

  /// 更新音量
  void _updateVolume(double value) {
    setState(() {
      _volume = value;
      _ttsEngine.setVolume(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 文本输入区域
            TextField(
              controller: _textController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: '请输入要合成的文本',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),

            // 状态文本
            Text(
              _statusText,
              style: TextStyle(
                color: _isSynthesizing ? Colors.blue : Colors.black,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 24),

            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isSynthesizing ? null : _synthesizeText,
                  child: Text('合成'),
                ),
                ElevatedButton(
                  onPressed: _audioData == null || _isPlaying ? null : _playAudio,
                  child: Text('播放'),
                ),
                ElevatedButton(
                  onPressed: !_isPlaying ? null : _pauseAudio,
                  child: Text('暂停'),
                ),
                ElevatedButton(
                  onPressed: !_isPaused ? null : _resumeAudio,
                  child: Text('继续'),
                ),
                ElevatedButton(
                  onPressed: !_isPlaying && !_isPaused ? null : _stopAudio,
                  child: Text('停止'),
                ),
              ],
            ),
            SizedBox(height: 24),

            // 语速调节
            Row(
              children: [
                Text('语速: ${_speed.toStringAsFixed(1)}'),
                Expanded(
                  child: Slider(
                    value: _speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    onChanged: _updateSpeed,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // 音量调节
            Row(
              children: [
                Text('音量: ${_volume.toStringAsFixed(1)}'),
                Expanded(
                  child: Slider(
                    value: _volume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    onChanged: _updateVolume,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
