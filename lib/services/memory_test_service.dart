import 'package:flutter/material.dart';

import '../core/logger/app_logger.dart';
import '../models/message.dart';
import '../services/ai_service.dart';
import '../services/memu_service.dart';

class MemoryTestService extends ChangeNotifier {
  final MemUService _memuService;
  AiService _aiService;

  bool _isTesting = false;
  String _testResult = '';
  final List<String> _testReport = [];

  MemoryTestService({
    required MemUService memuService,
    required AiService aiService,
  }) : _memuService = memuService,
       _aiService = aiService;

  bool get isTesting => _isTesting;
  String get testResult => _testResult;
  List<String> get testReport => List.unmodifiable(_testReport);

  set testResult(String value) {
    _testResult = value;
    notifyListeners();
  }

  set aiService(AiService service) {
    _aiService = service;
  }

  void addTestReport(String message) {
    _testReport.add(message);
    notifyListeners();
  }

  void clearTestReport() {
    _testReport.clear();
    _testResult = '';
    notifyListeners();
  }

  Future<List<String>> _generateAiTestMemories(int count, String theme) async {
    try {
      final prompt = '''你是一个测试数据生成器。请生成 $count 条关于「$theme」的模拟用户记忆内容。

要求：
- 每条记忆是一句话，模拟真实用户的个人信息、偏好或经历
- 内容要多样化：包含姓名、年龄、职业、爱好、住址、家庭、习惯等不同维度
- 每条内容要有区分度，不要重复
- 使用中文
- 直接输出 $count 行，每行一条记忆，不要加序号和引号''';

      final response = await _aiService.chat([
        Message(role: 'system', content: '你是测试数据生成器，只输出原始数据行，不加任何格式。'),
        Message(role: 'user', content: prompt),
      ]);

      final lines = response
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => l.trim())
          .toList();

      return lines.take(count).toList();
    } catch (e) {
      AppLogger.e('[MemoryTestService] AI生成测试内容失败，使用备用方案: $e');
      return _fallbackTestMemories(count, theme);
    }
  }

  List<String> _fallbackTestMemories(int count, String theme) {
    final seed = theme.hashCode;
    final templates = [
      '$theme喜欢在周末去公园散步',
      '$theme每天早上7点准时起床',
      '$theme的工作地点在城市的商业区',
      '$theme养了一只宠物狗叫旺财',
      '$theme最近在学习一门新的编程语言',
      '$theme的手机号是138${(seed % 90000000 + 10000000).toString()}',
      '$theme毕业于本省的重点大学',
      '$theme喜欢吃辣的食物，尤其爱火锅',
      '$theme每个月会读两本书',
      '$theme的梦想是开一家自己的咖啡店',
      '$theme会弹吉他，大学时组过乐队',
      '$theme的老家在一个海边小城',
      '$theme有一辆白色的代步车',
      '$theme喜欢看科幻类的电影和小说',
      '$theme每周会和朋友们打一次篮球',
      '$theme最近在考虑换一份新工作',
      '$theme会用三种语言进行日常交流',
      '$theme的生日在春天',
      '$theme有一个双胞胎兄弟姐妹',
      '$theme收集各个城市的明信片',
      '$theme擅长做家常菜，特别是红烧肉',
      '$theme每天睡前会听半小时播客',
      '$theme的计划是明年出国旅行',
      '$theme小时候学过五年钢琴',
      '$theme最好的朋友是小学同学',
      '$theme住在城市的新开发区',
      '$theme喜欢喝冰美式咖啡',
      '$theme有一个习惯就是记账',
      '$theme最近迷上了摄影',
      '$theme的公司每年组织一次团建',
    ];
    return templates.take(count).toList();
  }

  Future<void> startBasicMemoryTest() async {
    _isTesting = true;
    clearTestReport();
    addTestReport('开始基础记忆写入提取测试（25条测试记忆）...');
    notifyListeners();

    try {
      addTestReport('清理旧的测试记忆...');
      await _memuService.clearAllTestMemory();
      notifyListeners();

      final testConvId = _memuService.createTempConversation();
      addTestReport('创建临时会话: $testConvId');

      addTestReport('正在通过AI生成测试记忆...');
      notifyListeners();
      final testMemories = await _generateAiTestMemories(25, '一个叫张三的25岁软件工程师');
      addTestReport('AI生成 ${testMemories.length} 条测试记忆');

      for (var i = 0; i < testMemories.length; i++) {
        await _memuService.addTestMemory(
          conversationId: testConvId,
          content: testMemories[i],
          type: i % 3 == 0 ? MemoryType.longTerm : MemoryType.shortTerm,
          importance: 0.4 + (i % 6) * 0.1,
        );
        if (i % 5 == 0) {
          addTestReport('已写入 ${i + 1}/${testMemories.length} 条记忆');
          notifyListeners();
        }
      }
      addTestReport('全部 ${testMemories.length} 条记忆写入完成');

      final testQueries = [
        '用户叫什么名字？',
        '他住在哪里？',
        '他的职业是什么？',
        '他喜欢做什么？',
        '他养宠物吗？',
      ];

      int successCount = 0;
      for (var i = 0; i < testQueries.length; i++) {
        final extractedMemories = await _memuService.extractTestMemory(
          testConvId,
          testQueries[i],
        );
        if (extractedMemories.isNotEmpty) {
          successCount++;
          addTestReport(
            '查询 ${i + 1}: "${testQueries[i]}" -> 找到 ${extractedMemories.length} 条相关记忆',
          );
        } else {
          addTestReport('查询 ${i + 1}: "${testQueries[i]}" -> 未找到相关记忆');
        }
        notifyListeners();
      }

      if (successCount >= 3) {
        addTestReport('基础记忆测试通过！（$successCount/${testQueries.length} 查询成功）');
        testResult = '基础记忆测试通过！';
      } else {
        addTestReport('基础记忆测试失败！（$successCount/${testQueries.length} 查询成功）');
        testResult = '基础记忆测试失败！';
      }
    } catch (e) {
      addTestReport('测试异常: $e');
      testResult = '基础记忆测试异常！';
    }

    _isTesting = false;
    notifyListeners();
  }

  Future<void> startIsolationTest() async {
    _isTesting = true;
    clearTestReport();
    addTestReport('开始会话隔离测试（每个会话15条记忆）...');
    notifyListeners();

    try {
      addTestReport('清理旧的测试记忆...');
      await _memuService.clearAllTestMemory();
      notifyListeners();

      final convId1 = _memuService.createTempConversation();
      final convId2 = _memuService.createTempConversation();
      addTestReport('创建两个临时会话');
      addTestReport('  会话 A: $convId1');
      addTestReport('  会话 B: $convId2');

      addTestReport('正在通过AI生成会话A的测试记忆（主题：小明）...');
      notifyListeners();
      final memoriesA = await _generateAiTestMemories(
        15,
        '小明，一个28岁的广州医生，喜欢足球和粤菜',
      );
      addTestReport('AI生成会话A ${memoriesA.length} 条记忆');

      addTestReport('正在通过AI生成会话B的测试记忆（主题：小红）...');
      notifyListeners();
      final memoriesB = await _generateAiTestMemories(
        15,
        '小红，一个24岁的成都设计师，喜欢画画和火锅',
      );
      addTestReport('AI生成会话B ${memoriesB.length} 条记忆');

      for (var i = 0; i < memoriesA.length; i++) {
        await _memuService.addTestMemory(
          conversationId: convId1,
          content: memoriesA[i],
          type: i % 4 == 0 ? MemoryType.longTerm : MemoryType.shortTerm,
          importance: 0.5 + (i % 5) * 0.1,
        );
      }
      addTestReport('会话 A 写入 ${memoriesA.length} 条记忆');
      notifyListeners();

      for (var i = 0; i < memoriesB.length; i++) {
        await _memuService.addTestMemory(
          conversationId: convId2,
          content: memoriesB[i],
          type: i % 4 == 0 ? MemoryType.longTerm : MemoryType.shortTerm,
          importance: 0.5 + (i % 5) * 0.1,
        );
      }
      addTestReport('会话 B 写入 ${memoriesB.length} 条记忆');
      notifyListeners();

      final allTestMemories = await _memuService.getAllTestMemories();
      addTestReport('数据库中共有 ${allTestMemories.length} 条测试记忆');

      int convACount = 0;
      int convBCount = 0;
      bool hasLeakage = false;

      for (var m in allTestMemories) {
        if (m.conversationId == convId1) {
          convACount++;
          if (m.content.contains('小红') || m.content.contains('成都')) {
            hasLeakage = true;
            addTestReport('会话 A 中发现会话 B 的记忆: ${m.content}');
          }
        } else if (m.conversationId == convId2) {
          convBCount++;
          if (m.content.contains('小明') || m.content.contains('广州')) {
            hasLeakage = true;
            addTestReport('会话 B 中发现会话 A 的记忆: ${m.content}');
          }
        }
      }

      addTestReport('会话 A 实际存储: $convACount 条');
      addTestReport('会话 B 实际存储: $convBCount 条');

      if (!hasLeakage &&
          convACount == memoriesA.length &&
          convBCount == memoriesB.length) {
        addTestReport('会话隔离验证通过！两个会话记忆完全独立');
        testResult = '会话隔离测试通过！';
      } else {
        addTestReport('会话隔离验证失败！');
        testResult = '会话隔离测试失败！';
      }
    } catch (e) {
      addTestReport('测试异常: $e');
      testResult = '会话隔离测试异常！';
    }

    _isTesting = false;
    notifyListeners();
  }

  Future<void> startShortLongTermTest() async {
    _isTesting = true;
    clearTestReport();
    addTestReport('开始短长期记忆测试（20条记忆：10短期+10长期）...');
    notifyListeners();

    try {
      addTestReport('清理旧的测试记忆...');
      await _memuService.clearAllTestMemory();
      notifyListeners();

      final testConvId = _memuService.createTempConversation();
      addTestReport('创建临时会话: $testConvId');

      addTestReport('正在通过AI生成短期+长期测试记忆...');
      notifyListeners();
      final allTestContent = await _generateAiTestMemories(
        20,
        '王小华，一个1995年出生的杭州人，在阿里巴巴工作',
      );

      final shortTermMemories = allTestContent.take(10).toList();
      final longTermMemories = allTestContent.skip(10).take(10).toList();

      for (var i = 0; i < shortTermMemories.length; i++) {
        await _memuService.addTestMemory(
          conversationId: testConvId,
          content: shortTermMemories[i],
          type: MemoryType.shortTerm,
          importance: 0.2 + (i % 3) * 0.1,
        );
      }
      addTestReport(
        '写入 ${shortTermMemories.length} 条短期记忆 (importance: 0.2-0.4)',
      );
      notifyListeners();

      for (var i = 0; i < longTermMemories.length; i++) {
        await _memuService.addTestMemory(
          conversationId: testConvId,
          content: longTermMemories[i],
          type: MemoryType.longTerm,
          importance: 0.7 + (i % 3) * 0.1,
        );
      }
      addTestReport(
        '写入 ${longTermMemories.length} 条长期记忆 (importance: 0.7-0.9)',
      );
      notifyListeners();

      final allMemories = await _memuService.getAllTestMemories();
      addTestReport('数据库中共有 ${allMemories.length} 条测试记忆');

      int shortCount = 0;
      int longCount = 0;
      double avgShortImportance = 0;
      double avgLongImportance = 0;

      for (var m in allMemories) {
        if (m.type == MemoryType.shortTerm) {
          shortCount++;
          avgShortImportance += m.importance;
        }
        if (m.type == MemoryType.longTerm) {
          longCount++;
          avgLongImportance += m.importance;
        }
      }

      avgShortImportance = shortCount > 0 ? avgShortImportance / shortCount : 0;
      avgLongImportance = longCount > 0 ? avgLongImportance / longCount : 0;

      addTestReport(
        '短期记忆: $shortCount 条, 平均重要性: ${avgShortImportance.toStringAsFixed(2)}',
      );
      addTestReport(
        '长期记忆: $longCount 条, 平均重要性: ${avgLongImportance.toStringAsFixed(2)}',
      );

      if (shortCount >= 8 &&
          longCount >= 8 &&
          avgLongImportance > avgShortImportance) {
        addTestReport('短长期记忆验证通过！类型和重要性区分正确');
        testResult = '短长期记忆测试通过！';
      } else {
        addTestReport('短长期记忆验证失败！');
        testResult = '短长期记忆测试失败！';
      }
    } catch (e) {
      addTestReport('测试异常: $e');
      testResult = '短长期记忆测试异常！';
    }

    _isTesting = false;
    notifyListeners();
  }

  Future<void> startFuzzyMatchTest() async {
    _isTesting = true;
    clearTestReport();
    addTestReport('开始模糊匹配测试（20条记忆 + 6个查询测试）...');
    notifyListeners();

    try {
      addTestReport('清理旧的测试记忆...');
      await _memuService.clearAllTestMemory();
      notifyListeners();

      final testConvId = _memuService.createTempConversation();
      addTestReport('创建临时会话: $testConvId');

      addTestReport('正在通过AI生成模糊匹配测试记忆（多主题）...');
      notifyListeners();
      final testMemories = await _generateAiTestMemories(
        20,
        '包含水果、食物、运动、颜色等多主题的多样化用户偏好信息',
      );
      addTestReport('AI生成 ${testMemories.length} 条多主题测试记忆');

      for (var i = 0; i < testMemories.length; i++) {
        await _memuService.addTestMemory(
          conversationId: testConvId,
          content: testMemories[i],
          type: i % 3 == 0 ? MemoryType.longTerm : MemoryType.shortTerm,
          importance: 0.4 + (i % 6) * 0.1,
        );
        if (i % 5 == 0) {
          addTestReport('已写入 ${i + 1}/${testMemories.length} 条记忆');
          notifyListeners();
        }
      }
      addTestReport('全部 ${testMemories.length} 条记忆写入完成');
      notifyListeners();

      final testQueries = ['水果', '运动', '颜色', '吃饭', '喜欢的东西', '日常习惯'];

      int totalSuccess = 0;
      for (var i = 0; i < testQueries.length; i++) {
        final query = testQueries[i];

        final memories = await _memuService.extractTestMemory(
          testConvId,
          query,
        );

        if (memories.isNotEmpty) {
          totalSuccess++;
          addTestReport('查询 ${i + 1}: "$query" -> 找到 ${memories.length} 条相关记忆');
        } else {
          addTestReport('查询 ${i + 1}: "$query" -> 未找到匹配记忆');
        }
        notifyListeners();
      }

      if (totalSuccess >= 4) {
        addTestReport('模糊匹配测试通过！（$totalSuccess/${testQueries.length} 查询成功）');
        testResult = '模糊匹配测试通过！';
      } else {
        addTestReport('模糊匹配测试失败！（$totalSuccess/${testQueries.length} 查询成功）');
        testResult = '模糊匹配测试失败！';
      }
    } catch (e) {
      addTestReport('测试异常: $e');
      testResult = '模糊匹配测试异常！';
    }

    _isTesting = false;
    notifyListeners();
  }

  Future<void> startAllTest() async {
    _isTesting = true;
    clearTestReport();
    addTestReport('开始执行所有记忆功能测试...');
    notifyListeners();

    await startBasicMemoryTest();
    await Future.delayed(const Duration(milliseconds: 500));
    await startIsolationTest();
    await Future.delayed(const Duration(milliseconds: 500));
    await startShortLongTermTest();
    await Future.delayed(const Duration(milliseconds: 500));
    await startFuzzyMatchTest();

    _isTesting = false;
    notifyListeners();
  }

  Future<void> clearTestMemory() async {
    _isTesting = true;
    clearTestReport();
    addTestReport('开始清理测试记忆...');
    notifyListeners();

    try {
      await _memuService.clearAllTestMemory();
      addTestReport('测试记忆清理完成！');
      testResult = '清理完成！';
    } catch (e) {
      addTestReport('清理异常: $e');
      testResult = '清理失败！';
    }

    _isTesting = false;
    notifyListeners();
  }
}
