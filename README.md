
### app notice 通知类型
值	显示名称	弹窗图标及颜色
info	告知	信息图标，主题色
warning	警告	警告三角形，错误强调色
important	重要	感叹号，错误强调色
urgent	非常重要	感叹号，错误强调色

### json样例
{
"schemaVersion": 1,
"notices": [
{
"id": "notice-example-001",
"title": "通知示例",
"content": "这是公告格式示例。发布时请替换为正式内容、设置发布时间，并将 enabled 改为 true。",
"type": "info",
"closeDelaySeconds": 5,
"repeatEnabled": true,
"repeatCount": 5,
"publishedAt": "2026-09-17T10:00:00+08:00",
"expiresAt": null,
"enabled": true
},
{
"id": "notice-example-002",
"title": "通知示例",
"content": "这是公告格式示例。发布时请替换为正式内容、设置发布时间，并将 enabled 改为 true。",
"type": "important",
"closeDelaySeconds": 5,
"repeatEnabled": true,
"repeatCount": 3,
"publishedAt": "2026-09-18T10:00:00+08:00",
"expiresAt": null,
"enabled": true
}
]
}