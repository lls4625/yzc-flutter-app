import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

// Only fixed, user-facing labels may leave this boundary. Never return exception text.
String userError(Object? error, {String fallback = '操作失败，请重试'}) {
  final message = error is StateError ? error.message.toString()
      : error is FormatException ? error.message
      : error is PlatformException ? error.message ?? ''
      : '';
  if (message.contains('空间不足')) return '存储空间不足';
  if (message.startsWith('解压失败') || message.startsWith('解压进程')) return '解压失败';
  if (message.contains('密码密文')) return '资源包配置异常';
  if (message.contains('下载地址无效')) return '下载地址配置异常';
  if (message.contains('不存在或不可下载')) return '内容暂不可下载';
  if (message.contains('目录名')) return '学习资源配置异常';
  if (message.contains('请等待当前内容任务完成') || message.contains('内容正在')) return '内容正在处理，请稍后再试';
  if (message.contains('内容未安装') || message == '请先下载内容') return '内容暂不可用';
  if (message.contains('缺少音频') || message.contains('音频文件缺失') || message.contains('音频丢失') || message.contains('音频备份缺失')) return '音频资源缺失';
  if (message == '本条暂无音频' || message == '当前没有可播放的音频') return '暂无可播放的音频';
  if (message.startsWith('原课程已不在')) return '原课程已不在当前内容中';
  if (message == '暂无错题') return '暂无错题';
  if (message == '暂无到期复习题') return '暂无到期复习题';
  if (message.startsWith('本课需至少') || message == '本课暂无可用题目') return '本课可用题目不足';
  if (message.startsWith('题库已更新')) return '题库已更新，请重新打开课程';
  if (message == '练习记录为空' || message == '练习快照不存在') return '练习记录暂不可用';
  if (message == '只能评价已提交的错题') return '请先提交错题答案';
  if (error is TimeoutException) return '连接超时';
  if (error is SocketException || error is HandshakeException) return '网络连接失败';
  if (error is HttpException) return '服务器请求失败';
  if (error is FileSystemException) return '文件读写失败';
  if (error is DatabaseException) return '本地数据处理失败';
  if (error is PlatformException && error.code == 'lesson_audio') return '音频播放失败';
  if (error is FormatException) return '数据格式异常';
  return fallback;
}
