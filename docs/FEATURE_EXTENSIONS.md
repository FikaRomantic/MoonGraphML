# 原子节点重命名与边子图抽取

## 原子批量节点重命名

`Document::relabel_nodes(root, replacements, limits~)` 在一个顶层图的节点 ID
作用域中执行同时替换，支持交换和循环命名。所有普通边、嵌套图和超边端点引用
按原始映射应用一次。未知来源、重复来源、非法目标以及最终 ID 冲突明确报错；
原文档不可变，失败不会留下半更新图。失效的 `parse.nodeids` 提示被移除。

用于多来源图数据迁移、稳定 ID 归一化、设备或服务重新编号。端口名称保持原值；
XML 属性载荷中的业务字符串或自定义引用不会被猜测性修改。完整结果再次验证。
映射和结构变换为 O(V+E+H+M) 期望时间、O(V+E+H+M) 空间，其中 H 为超边
端点数量、M 为替换数；完整索引构建/文档验证及属性载荷复制成本另计。

## 按边抽取子图

`FlatGraph::edge_subgraph(edge_indices, keep_isolated~, limits~)` 以源边索引
选择子图，匿名边和平行边可分别选择；结果遵循源顺序，默认仅保留选中边的端点，
可选择保留全部孤立节点。保留类型定义、默认值和 XML 元数据，清理过时拓扑提示。
重复与越界索引被拒绝，空选集有效。输入遵守 `FlatGraph` 原有范围，不接收层级图、
端口或超边。根 Document 的扩展元数据本来不属于 FlatGraph 视图。

适用于链路采样、关系筛选、图算法结果导出和事件相关边的共享。
扫描源节点/边和选择表为 O(V+E+S) 期望时间、O(V+E+S) 上界空间，
输出再次验证并遵守资源限制；属性载荷复制开销另计。

## 验证范围

`selection_relabel_wbtest.mbt` 覆盖 ID 交换、端口/超边引用、冲突后的原图不变、
平行边、自环、孤立点选项、非法选择和 GraphML 序列化重读。

## 本地复现

要求 moonc >= 0.10.16。在本地源码目录执行：

```sh
moon update
python tools/verify_toolchain.py
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon run examples/selection --target wasm-gc --deny-warn
moon run examples/selection --target native --deny-warn
```

Windows 如遇 OCaml 扩展路径问题，使用仓库提供的 `tools/windows/moon.ps1`
代替 `moon`；没有该脚本的仓库建议在 Linux/WSL 环境运行上述命令。
这些是源码工作区新增 API，现有已发布版本号未变；发布新版本后才可从 Mooncakes
安装取得这些新增功能。全部示例为可运行断言，不代表已有生产部署。
