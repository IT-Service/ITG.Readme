﻿Import-LocalizedData `
    -BindingVariable loc `
;

$Translator = @{
	RegExp = $null;
	RuleType = @();
	RegExpResults = @{};
	RegExpIds = @();
	Refs = @{};
	Rules = @{};
	TokenRules = @{};
};

$reTokenChar = '[-a-zA-Z0-9_]';
$reBeforeToken = "(?<!${reTokenChar}|^\t+.*?|(?:``.*?``)*?.*?``)";
$reAfterToken = "(?!${reTokenChar})";
$reBeforeURL = "(?<!${reTokenChar}|^\t+.*?|\(<?|<|(``.*?``)*?.*?``)";

$reRegExpId = New-Object System.Text.RegularExpressions.Regex -ArgumentList `
	'(?<=\(\?\<)(?<id>\w+)(?=\>)' `
	, ( [System.Text.RegularExpressions.RegexOptions]::IgnoreCase `
		-bor [System.Text.RegularExpressions.RegexOptions]::Multiline `
	) `
;

$reEOLCheck = New-Object System.Text.RegularExpressions.Regex -ArgumentList `
	'(?<crlf>\r?\n)' `
	, ( [System.Text.RegularExpressions.RegexOptions]::Singleline ) `
;

$reOnlineHelpLinkCheck = New-Object System.Text.RegularExpressions.Regex -ArgumentList `
	"^${reURL}`$" `
	, ( [System.Text.RegularExpressions.RegexOptions]::Singleline ) `
;

Filter ConvertTo-TranslateRule {
	<#
		.Synopsis
			Преобразует правила выделения внешних ссылок, переданных по конвейеру в различных форматах, в унифицированный формат
			для последующей инициализации транслятора `$Translator` (через Use-TranslateRule).
	#>
	param (
		[Parameter(
			Mandatory = $false
			, ValueFromPipeline = $true
		)]
		[Hashtable]
		$TranslateRule
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$ruleCategory = 'token'
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$ruleType
	,
		[Parameter(
			Mandatory = $true
			, ValueFromPipeline = $true
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		[Alias('Name')]
		$template
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipeline = $true
		)]
		[System.Management.Automation.FunctionInfo]
		$FunctionInfo
	,
		# Генерировать правила для формирования ссылок как на функции внешнего модуля
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[switch]
		$AsExternalModule
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$ModuleName
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[PSModuleInfo]
		$Module
,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$id
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$expression
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$url
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$title
	)
	
	if ( $TranslateRule ) {
		$null = $PSBoundParameters.Remove( 'TranslateRule' );
		$null = $PSBoundParameters.Remove( 'template' );
		return `
			New-Object PSObject -Property $TranslateRule `
			| ConvertTo-TranslateRule @PSBoundParameters `
		;
	} else {
		$PSBoundParameters.ruleCategory = $ruleCategory;
		if ( $FunctionInfo ) {
			$PSBoundParameters.ruleType = 'func';
		};
		if ( $ruleCategory -eq 'regExp' ) {
			if ( $template -match $reRegExpId ) {
				$PSBoundParameters.id = $Matches['id'];
			};
		};
		return New-Object PSObject -Property $PSBoundParameters;
	};
}

Function Add-EndReference {
	<#
		.Synopsis
			Добавляет в `$Translator` концевую ссылку, упоминание которой встречено в обрабатываемом тексте.
	#>
	param (
		[Parameter(
			Mandatory = $false
			, ValueFromPipeline = $true
		)]
		[Hashtable]
		$EndReference
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$id
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$url
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$title
	,
		[Parameter(
			Mandatory = $false
			, ValueFromPipelineByPropertyName = $true
		)]
		[String]
		$refType
	)
	
	process {
		if ( $EndReference ) {
			New-Object PSObject -Property $EndReference `
			| Add-EndReference `
			;
		} else {
			if ( -not $Translator.Refs.$id ) {
				$Translator.Refs.Add(
					$id
					, ( New-Object PSObject `
						-Property @{
							id = $id;
							refType = $refType;
							url = $url;
							title = $title;
						}
					)
				)
			};
		};
	}
}

Function Get-EndReference {
	<#
		.Synopsis
			Генерирует массив накопленных в `$Translator` концевых ссылок для включения в readme.
	#>
	$Translator.Refs.Values `
	| Group-Object -Property refType `
	| Sort-Object -Property Name `
	| % {
@"

"@
		$_.Group `
		| Sort-Object -Property id `
		| % {
			"[$( $_.id )]: $( $_.url )" `
			, ( & { if ( $_.title ) { "`"$( $_.title )`"" }; } ) `
			-join ' '
		};
	};
};

Function Use-TranslateRule {
	<#
		.Synopsis
			Инициализирует объект `$Translator` набором правил трансляции, поступившим по конвейеру.
	#>
	param (
		# элементы словаря (правил словаря - в том числе)
		[Parameter(
			Mandatory=$true
			, ValueFromPipeline=$true
		)]
		[PSObject]
		$TranslateRule
	)

	begin {
		$Translator.RegExp = $null;
		$Translator.RuleType = @();
		$Translator.RegExpResults = @{};
		$Translator.RegExpIds = @();
		$Translator.Refs = @{};
		$Translator.Rules = @{};
		$Translator.TokenRules = @{};

		$Rules = @();
	}
	process {
		$Rules += $TranslateRule;
	}
	end {
		$Translator.Rules = 
			$Rules `
			| Group-Object `
				-Property ruleCategory `
				-AsHashTable `
				-AsString `
		;
		$TokenRules = `
			$Translator.Rules.token `
			| Group-Object `
				-Property ruleType `
				-AsHashTable `
				-AsString `
		;
		foreach ( $ruleType in $TokenRules.Keys ) {
			$Translator.TokenRules.Add(
				$ruleType
				, (
					$TokenRules.$ruleType `
					| Group-Object `
						-Property template `
					| ForEach-Object `
						-Begin {
							$res = @{};
						} `
						-Process {
							$res.Add( $_.Name, $_.Group[0] );
						} `
						-End {
							$res;
						} `
				)
			);
		};
		$Translator.RegExp = New-Object `
			-TypeName System.Text.RegularExpressions.Regex `
			-ArgumentList `
				(
					(
						@( $Translator.Rules.regexp | Select-Object -ExpandProperty template ) `
						+ (
							$reBeforeToken `
							, '(?<token>' `
							, (
								(
									$Translator.Rules.token `
									| Group-Object -Property ruleType `
									| % {
										"(?<$( $_.Name )>$( ( $_.Group | % { $_.template } ) -join '|' ))";
									} `
								) -join '|' `
							) `
							, ')' `
							, $reAfterToken `
							-join '' `
						) `
					) -join '|' `
				) `
				, (
					[System.Text.RegularExpressions.RegexOptions]::IgnoreCase `
					-bor [System.Text.RegularExpressions.RegexOptions]::Multiline `
					-bor [System.Text.RegularExpressions.RegexOptions]::ExplicitCapture `
				)
		;
		$Translator.RuleType = `
			$Translator.Rules.token `
			| Select-Object -ExpandProperty ruleType -Unique `
		;
		$Translator.RegExpIds = `
			$Translator.Rules.regexp `
			| Select-Object -ExpandProperty id -Unique `
		;
		$Translator.RegExpResults = `
			$Translator.Rules.regexp `
			| ? { $_.id } `
			| Group-Object `
				-Property id `
			| ForEach-Object `
				-Begin {
					$res = @{};
				} `
				-Process {
					$res.Add( $_.Name, $_.Group[0] );
				} `
				-End {
					$res;
				} `
		;
	}
}

Filter Expand-Definitions {
	<#
		.Synopsis
			Данная функция выделяет определения из подготовленного readme и оформляет их в соответствии со 
			словарём, использованным при подготовке транслятора.
	#>
	
	param (
		# трансформируемый текст readme
		[Parameter(
			Mandatory=$true
			, ValueFromPipeline=$true
		)]
		[String]
		[AllowEmptyString()]
		$InputObject
	)

	if ( -not [String]::IsNullOrEmpty( $InputObject ) ) {
		$Translator.RegExp.Replace(
			( $reEOLCheck.Replace( $InputObject, "`r`n" ) ) `
			, {
				param( [System.Text.RegularExpressions.Match] $Match)
				foreach ( $RuleType in $Translator.RegExpIds ) {
					if ( $Match.Groups[$RuleType].Success ) {
						if ( $Translator.RegExpResults.$RuleType.expression -eq $null ) {
							return ( & "MatchEvaluatorFor$RuleType" $Match );
						} else {
							if ( $ruleType -eq 'mdRef' ) {
								$a=1;
							};
							return $Match.Result( $Translator.RegExpResults.$RuleType.expression );
						};
					}
				};
				foreach ( $RuleType in $Translator.RuleType ) {
					if ( $Match.Groups[$RuleType].Success ) {
						return ( & "MatchEvaluatorFor$RuleType" $Match );
					}
				};
			}
		);
	};
};

$PowerShellAboutTopics = @{
	'about_Aliases' = 113207
	'about_Arithmetic_Operators' = 113208
	'about_Arrays' = 113209
	'about_Assignment_Operators' = 113210
	'about_Automatic_Variables' = 113212
	'about_Break' = 113213
	'about_Command_Precedence' = 113214
	'about_Command_Syntax' = 113215
	'about_Comment_Based_Help' = 144309
	'about_CommonParameters' = 113216
	'about_Comparison_Operators' = 113217
	'about_Continue' = 113218
	'about_Core_Commands' = 113219
	'about_Data_Sections' = 113220
	'about_Debuggers' = 113221
	'about_Do' = 135169
	'about_Environment_Variables' = 113222
	'about_Escape_Characters' = 113223
	'about_EventLogs' = 113224
	'about_Execution_Policies' = 135170
	'about_For' = 113228
	'about_Foreach' = 113229
	'about_Format.ps1xml' = 113230
	'about_Functions' = 113231
	'about_Functions_Advanced' = 144511
	'about_Functions_Advanced_Methods' = 135172
	'about_Functions_Advanced_Parameters' = 135173
	'about_Functions_CmdletBindingAttribute' = 135174
	'about_Hash_Tables' = 135175
	'about_History' = 113233
	'about_If' = 113234
	'about_Job_Details' = 135176
	'about_jobs' = 113251
	'about_Join' = 113235
	'about_Language_Keywords' = 136588
	'about_Line_Editing' = 113236
	'about_Locations' = 113237
	'about_Logical_Operators' = 113238
	'about_Methods' = 113239
	'about_Modules' = 144311
	'about_Objects' = 113241
	'about_Operators' = 113242
	'about_Parameters' = 113243
	'about_Parsing' = 113244
	'about_Path_Syntax' = 113245
	'about_Pipelines' = 113246
	'about_Preference_Variables' = 113248
	'about_Profiles' = 113729
	'about_Prompts' = 135179
	'about_Properties' = 113249
	'about_Providers' = 113250
	'about_PSSession_Details' = 135180
	'about_PSSessions' = 135181
	'about_PSsnapins' = 113252
	'about_Quoting_Rules' = 113253
	'about_Redirection' = 113254
	'about_Ref' = 113255
	'about_Regular_Expressions' = 113256
	'about_Remote' = 135182
	'about_Remote_FAQ' = 135183
	'about_Remote_Jobs' = 135184
	'about_Remote_Output' = 135185
	'about_Remote_Requirements' = 135187
	'about_Remote_Troubleshooting' = 135188
	'about_Requires' = 135190
	'about_Reserved_Words' = 113258
	'about_Return' = 136587
	'about_Scopes' = 113260
	'about_Script_Blocks' = 113261
	'about_Script_Internationalization' = 113262
	'about_Scripts' = 144310
	'about_Session_Configurations' = 145152
	'about_Signing' = 113268
	'about_Special_Characters' = 113269
	'about_Split' = 113270
	'about_Switch' = 113271
	'about_Throw' = 145153
	'about_Transactions' = 135192
	'about_Trap' = 136586
	'about_Try_Catch_Finally' = 113444
	'about_Type_Operators' = 113273
	'about_Types.ps1xml' = 113274
    'about_Updatable_Help' = 235801
	'about_Variables' = 157591
	'about_While' = 113275
	'about_Wildcards' = 113276
	'about_Windows_Powershell_2.0' = 113247
	'about_Windows_PowerShell_ISE' = 135178
	'about_WMI_Cmdlets' = 145766
	'about_WS-Management_Cmdlets' = 145774
};

Function MatchEvaluatorForAbout( [System.Text.RegularExpressions.Match] $Match ) {
	$id = `
		$PowerShellAboutTopics.Keys `
		| ? { $_ -ieq ($Match.Groups['about'].Value) } `
	;
	if ( $id ) {
		Add-EndReferenceForAbout( $id );
		return "[${id}][]";
	} else {
		Write-Warning `
			-Message @"
$loc.WarningUnknownAboutTerm

	$( $Match.Groups['about'].Value )
	
"@ `
		;
		return ( $Match.Groups['about'].Value );
	};
};

Function Add-EndReferenceForAbout( [String] $Id ) {
	$aboutTopic = Get-Help `
		-Category HelpFile `
		-Name $id `
		-Full `
		-ErrorAction SilentlyContinue `
	;
	$title = $aboutTopic.Synopsis;
	if ( $title -match '[^.]\s*$' ) {
		$title += '...';
	};
	Add-EndReference `
		-id $id `
		-url "http://go.microsoft.com/fwlink/?LinkID=$( $PowerShellAboutTopics[ $id ] )" `
		-title $title `
	;
};

Function MatchEvaluatorForAboutCP( [System.Text.RegularExpressions.Match] $Match ) {
	Add-EndReferenceForAbout( 'about_CommonParameters' );
	return '[about_CommonParameters][]';
};

$PowerShellAboutTopicsTranslateRules = @(
	'about_[a-zA-Z_.]+?' `
	| ConvertTo-TranslateRule -ruleType 'about' `
);

# [test]: <http://novgaro.ru> "заголовок такой"
$reMDRefTitle = "(?:'(?<title>.+?)'|`"(?<title>.+?)`"|\((?<title>.+?)\))";
$reMDRef = New-Object System.Text.RegularExpressions.Regex -ArgumentList `
	"(?<=^\s*)(?<mdRef>\[(?<id>.+?)\]:\s+(?:<$reURL>|$reURL)(?:\s+$reMDRefTitle)?)(?=\s*$)" `
	, ( [System.Text.RegularExpressions.RegexOptions]::IgnoreCase `
		-bor [System.Text.RegularExpressions.RegexOptions]::Multiline `
	) `
;
$reMDLink = New-Object System.Text.RegularExpressions.Regex -ArgumentList `
	"(?<mdLink>\[(?<id>.+?)\]\((?:<$reURL>|$reURL)\))" `
	, ( [System.Text.RegularExpressions.RegexOptions]::IgnoreCase `
		-bor [System.Text.RegularExpressions.RegexOptions]::Multiline `
	) `
;

$BasicTranslateRules = `
	(
		  @{ template='(?<ts>[ \t]+)(?=\r?$)'; expression='' } `
		, @{ template='(?<=(\r?\n))(?<eol>(?:[ \t]*\r?\n)+)'; expression="`r`n" } `
		, @{ template='(?<aboutCP>"get-help about_CommonParameters")' } `
		, @{ template='(?<aboutCP>about_CommonParameters(?:\s+[(].*?[)])?)' } `
		, @{ template="${reMDRef}"; expression='[${id}][]' } `
		, @{ template="${reMDLink}"; expression='[${id}](${url})' } `
		, @{ template="${reBeforeURL}(?<fullUrl>${reURL})"; expression='<${fullUrl}>' } `
		, @{ template="${reBeforeURL}(?<wwwUrl>${reURLShortHTTP})"; expression='<http://${wwwUrl}>' } `
		, @{ template="${reBeforeURL}(?<ftpUrl>${reURLShortFTP})"; expression='<ftp://${ftpUrl}>' } `
		| ConvertTo-TranslateRule -ruleCategory regExp `
	) `
	+ $PowerShellAboutTopicsTranslateRules `
;

Function MatchEvaluatorForFunc( [System.Text.RegularExpressions.Match] $Match ) {
	$id = $Match.Groups['func'].Value;
	$title = ( ( Get-Help $id ).Synopsis -split '\s*\r?\n' ) -join ' ';
    $ModuleReadmeURL = '';
    if ( $Translator.TokenRules.func.$id.AsExternalModule ) {
        $ModuleReadmeURL = $Translator.TokenRules.func.$id.Module.PrivateData.ReadmeURL;
        if ( -not $ModuleReadmeURL ) {
    		Write-Warning `
	    		-Message @"
$( [String]::Format( $loc.WarningUnknownModuleReadmeURL, $Translator.TokenRules.func.$id.Module.Name ) )

PrivateData = @{
    ReadmeURL = 'https://github.com/$( $Translator.TokenRules.func.$id.Module.CompanyName )/$( $Translator.TokenRules.func.$id.Module.Name )';
}
	
"@ `
    		;
            $ModuleReadmeURL = "https://github.com/IT-Service/$( $Translator.TokenRules.func.$id.Module.Name )";
        };
    };
	Add-EndReference `
		-id $id `
		-url "<$ModuleReadmeURL#$( $id.ToLower() )>" `
		-title $title `
	;
	return "[${id}][]";
};

Function Get-FunctionsReferenceTranslateRules {
	<#
		.Synopsis
			Данная функция возвращает правила формирования ссылок на функции модуля по
			описателю модуля.
	#>
	
	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, ValueFromPipeline=$true
		)]
		[PSModuleInfo]
		$ModuleInfo
	,
		# Генерировать правила для формирования ссылок как на функции внешнего модуля
		[switch]
		$AsExternalModule
	)

	process {
		$ModuleInfo.ExportedFunctions.Values `
		| ConvertTo-TranslateRule `
            -AsExternalModule:$AsExternalModule `
		;
	}
}

Function MatchEvaluatorForTag( [System.Text.RegularExpressions.Match] $Match ) {
	$id = $Match.Value;
	Add-EndReference `
		-id $id `
		-url $Translator.TokenRules.tag.$id.url `
		-title $Translator.TokenRules.tag.$id.title `
	;
	return "[${id}][]";
};

Function Get-TagReferenceTranslateRules {
	<#
		.Synopsis
			Данная функция возвращает правила замены терминов на ссылки [tag][] по найденным
			определениям типа `[test]: <http://novgaro.ru> "заголовок такой"`
	#>

	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		$ModuleInfo
	,
		# Описатель внешнего сценария
		[Parameter(
			Mandatory=$true
			, ValueFromPipeline=$true
			, ParameterSetName='ExternalScriptInfo'
		)]
		[System.Management.Automation.ExternalScriptInfo]
		$ExternalScriptInfo
	,
		# Описатель функции
		[Parameter(
			Mandatory=$true
			, ValueFromPipeline=$true
			, ParameterSetName='FunctionInfo'
		)]
		[System.Management.Automation.FunctionInfo]
		$FunctionInfo
	,
		# Текст для поиска ссылок
		[Parameter(
			Mandatory=$true
			, ValueFromPipeline=$true
			, ParameterSetName='StringInfo'
		)]
		[String]
		$Text
	)

	process {
		switch ( $PsCmdlet.ParameterSetName ) {
			'StringInfo' {
				$reMDRef.Matches( $Text ) `
				| % {
					@{
						template = ( $_.Groups['id'].Value );
						url = ( $_.Groups['url'].Value );
						title = ( $_.Groups['title'].Value );
					};
				} `
				| ConvertTo-TranslateRule `
					-ruleType 'tag' `
				;
			}
			'ModuleInfo' {
				$ModuleInfo.Description `
				| Get-TagReferenceTranslateRules;
				$ModuleInfo.ExportedFunctions.Values `
				| Get-TagReferenceTranslateRules;
			}
			'ExternalScriptInfo' {
			}
			'FunctionInfo' {
				$Help = $FunctionInfo | Get-Help -Full;
				$Help.Description `
				| Select-Object -ExpandProperty Text `
				| Get-TagReferenceTranslateRules `
				;
				$Help.relatedLinks `
				| Select-Object -ExpandProperty navigationLink `
				| ? { $_.LinkText } `
				| Select-Object -ExpandProperty LinkText `
				| Get-TagReferenceTranslateRules `
			};
		};
	}
}

$GetReadmeStatus = @{
	level = 0;
};

Function Get-Readme {
	<#
		.Synopsis
			Генерирует readme с MarkDown разметкой по данным модуля и комментариям к его функциям. 
		.Description
			Генерирует readme с MarkDown разметкой по данным модуля и комментариям к его функциям. 
			Предназначен, в частности, для размещения в репозиториях github. Для сохранения в файл
			используйте Set-Readme.
			Описание может быть сгенерировано функцией Get-Readme для модуля, функции, внешего сценария.
		.Functionality
			Readme
		.Role
			Everyone
		.Notes
		.Inputs
			System.Management.Automation.PSModuleInfo.
			Описатели модулей, для которых будет сгенерирован readme.md. 
			Получены описатели могут быть через Get-Module.
		.Inputs
			System.Management.Automation.ExternalScriptInfo.
			Описатели сценариев, для которых будет сгенерирован readme.md. 
		.Inputs
			System.Management.Automation.CmdletInfo.
			Описатели командлет, для которых будет сгенерирован readme.md. 
			Получены описатели могут быть через Get-Command.
		.Inputs
			System.Management.Automation.FunctionInfo.
			Описатели функций, для которых будет сгенерирован readme.md. 
			Получены описатели могут быть через Get-Command.
		.Outputs
			String.
			Содержимое readme.md.
		.Link
			[MarkDown]: <http://daringfireball.net/projects/markdown/syntax> "MarkDown (md) Syntax"
		.Link
			about_comment_based_help
		.Link
			[Написание справки для командлетов](http://go.microsoft.com/fwlink/?LinkID=123415)
		.Link
			http://github.com/IT-Service/ITG.Readme#Get-Readme
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | Get-Readme | Out-File -Path 'readme.md' -Encoding 'UTF8' -Width 1024;
			Генерация readme.md файла для модуля `ITG.Yandex.DnsServer` 
			в текущем каталоге.
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | Get-Readme -ReferencedModules @( 'ITG.Yandex', 'ITG.Utils', 'ITG.WinAPI.UrlMon', 'ITG.WinAPI.User32' | Get-Module )
			Генерация readme для модуля `ITG.Yandex.DnsServer`, при этом все упоминания
			функций модулей `ITG.Yandex`, `ITG.Utils`, `ITG.WinAPI.UrlMon`,
			`ITG.WinAPI.User32` так же будут заменены перекрёстными ссылками
			на readme.md указанных модулей.
	#>
	
	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		[Alias('Module')]
		$ModuleInfo
	,
		# Описатель внешнего сценария
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ExternalScriptInfo'
		)]
		[System.Management.Automation.ExternalScriptInfo]
		$ExternalScriptInfo
	,
		# Описатель функции
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='FunctionInfo'
		)]
		[System.Management.Automation.FunctionInfo]
		$FunctionInfo
	,
		# культура, для которой генерировать данные, на данный момент параметр задавать не следует.
		[Parameter(
			Mandatory=$false
		)]
		[System.Globalization.CultureInfo]
		$UICulture = ( Get-Culture )
	,
		# Генерировать только краткое описание
		[switch]
		[Alias('Short')]
		$ShortDescription
	,
		# Перечень модулей, упоминания функций которых будут заменены на ссылки
		[Parameter(
			Mandatory=$false
		)]
		[PSModuleInfo[]]
		$ReferencedModules = @()
	,
		# Правила для обработки readme регулярными выражениями
		[Parameter(
			Mandatory=$false
		)]
		[Array]
		$TranslateRules = @()
	)

	process {
		if ( -not $GetReadmeStatus.level ) {
		    if ( $PsCmdlet.ParameterSetName -eq 'ModuleInfo' ) {
                $ReferencedModules += $ModuleInfo.RequiredModules;
            };
			$TranslateRules += & {
				$ReferencedModules `
                | Sort-Object `
                    -Unique `
                    -Property Name `
				| % {
					$_ | Get-FunctionsReferenceTranslateRules -AsExternalModule;
					$_ | Get-TagReferenceTranslateRules;
				};
				switch ( $PsCmdlet.ParameterSetName ) {
					'ModuleInfo' {
						$ModuleInfo `
						| % {
							$_ | Get-FunctionsReferenceTranslateRules;
							$_ | Get-TagReferenceTranslateRules;
						};
					}
					'ExternalScriptInfo' {
					}
					'FunctionInfo' {
					};
				};
			};
			$TranslateRules = `
				@(
					$TranslateRules `
					| ConvertTo-TranslateRule `
				) `
				+ $BasicTranslateRules `
			;

			$TranslateRules `
			| Use-TranslateRule `
			;
			$res = $PSBoundParameters.Remove( 'TranslateRules' );
			$res = $PSBoundParameters.Remove( 'ReferencedModules' );
		};
		$GetReadmeStatus.level++;
		
		switch ( $PsCmdlet.ParameterSetName ) {
			'ModuleInfo' {
				$ReadMeContent = & { `
@"
$($ModuleInfo.Name)
$($ModuleInfo.Name -replace '.','=')

$( $ModuleInfo.Description | Expand-Definitions )

$( $loc.ModuleVersion ): **$( $ModuleInfo.Version.ToString() )**
"@
					if ( $ModuleInfo.ExportedFunctions ) {
@"

$( $loc.Funtions )
$( $loc.Funtions -replace '.','-')
"@
						# генерация краткого описания функций
						$ModuleInfo.ExportedFunctions.Values `
						| Sort-Object -Property `
							@{ Expression={ ( $_.Name -split '-' )[1] } } `
							, @{ Expression={ ( $_.Name -split '-' )[0] } } `
						| Group-Object -Property `
							@{ Expression={ ( $_.Name -split '-' )[1] } } `
						| % {
							if ( $_.Name ) {
@"

### $($_.Name)
"@
							};
							$_.Group `
							| % {
								$_ `
								| Get-Readme `
									-ShortDescription `
								;
								if ( -not $ShortDescription ) {
@"

$( [String]::Format( $loc.Details, ( $_.Name | Expand-Definitions ) ) )
"@
								};
							};
						};

						if ( -not $ShortDescription ) {
@"

$( $loc.FunctionsDescriptionFull )
$( $loc.FunctionsDescriptionFull -replace '.','-')
"@
							$ModuleInfo.ExportedFunctions.Values `
							| Sort-Object -Property `
								@{ Expression={ ( $_.Name -split '-' )[1] } } `
								, @{ Expression={ ( $_.Name -split '-' )[0] } } `
							| Get-Readme `
							;
						};
					};
				} `
				| Out-String `
				;
				$ReadMeContent;
			}
			'ExternalScriptInfo' {
			}
			'FunctionInfo' {
				$ReadMeContent = & { `
					$Help = ( $FunctionInfo | Get-Help -Full );
					if ( $Help.Syntax ) {
						$Syntax = (
							$Help.Syntax.SyntaxItem `
							| % {
								,$_.Name `
								+ ( 
									$_.Parameter `
									| % {
										#MamlCommandHelpInfo#parameter
										$name="-$($_.Name)";
										if ( $_.position -ne 'named' ) {
											$name="[$name]";
										};
										if ( $_.parameterValue ) {
											$param = "$name <$($_.parameterValue)>";
										} else {
											$param = "$name";
										};
										if ( $_.required -ne 'true' ) {
											$param = "[$param]";
										};
										$param;
									}
								) `
								+ ( & {
									if ( $FunctionInfo.CmdletBinding ) { '<CommonParameters>' }
								} ) `
								-join ' '
							}
						);
					} else {
						$Syntax = $Help.Synopsis;
					};
					if ( $ShortDescription ) {
@"

#### $( [String]::Format( $loc.Overview, ( $FunctionInfo.Name | Expand-Definitions ) ) )

"@
						$Help.Synopsis `
						| Expand-Definitions `
						;
						if ( $Help.Syntax ) {
							$Syntax `
							| % {
@"

	$_
"@
							};
						};
					} else {
@"

#### $( [String]::Format( $loc.FunctionDescriptionFull, $($FunctionInfo.Name) ) )

"@
						if ( $Help.Description ) {
							$Help.Description `
							| Select-Object -ExpandProperty Text `
							| Expand-Definitions `
							;
						} else {
							$Help.Synopsis `
							| Expand-Definitions `
							;
						};
@"

##### $( $loc.Syntax )
"@
						$Syntax `
						| % {
@"

	$_
"@
						};
						if ( $Help.Component ) {
@"

##### $( $loc.Component )

$($Help.Component)
"@
						};
						if ( $Help.Functionality ) {
							$Description = `
								$Help.Functionality `
							;
@"

##### $( $loc.Functionality )

$Description
"@
						};
						if ( $Help.Role ) {
@"

##### $( $loc.Role )

$( [String]::Format( $loc.RoleDetails, $Help.Role, $FunctionInfo.Name ) )
"@
						};
						if ( $Help.inputTypes ) {
@"

##### $( $loc.InputTypes )

"@
							$Help.inputTypes.inputType `
							| % {
								$Description = `
									$_.type.name `
									| Expand-Definitions `
								;
@"
- $Description
"@
							};
						};
						if ( $Help.returnValues ) {
@"

##### $( $loc.ReturnValues )

"@
							$Help.returnValues.returnValue `
							| % {
								$Description = `
									$_.type.name `
									| Expand-Definitions `
								;
@"
- $Description
"@
							};
						};
						if ( $Help.Parameters ) {
							$Description = `
								( $Help.Parameters | Out-String ) `
								-replace '<CommonParameters>', '-<CommonParameters>' `
								-replace '(?m)(?<=^)\p{Z}{4}-([^\r\n]+)?(?=\s*$)', '- `$1`' `
								-replace '(?<=\S)[ \t]{2,}(?=\S)', ' ' `
								| Expand-Definitions `
							;
@"

##### $( $loc.Parameters )
$Description
"@
						};
						if ( $Help.Examples ) {
							$Help.Examples.Example `
							| % -Begin {
								$ExNum=0;
@"

##### $( $loc.Examples )
"@
							} `
							-Process {
								++$ExNum;
								$Comment = (
									(
										$_.remarks `
										| Select-Object -ExpandProperty Text `
										| ? { $_ } `
									) -join ' ' `
								).Trim( ' ', (("`t").Normalize()) ) `
								| Expand-Definitions `
								;
								if ( $Comment ) {
@"

$ExNum. $Comment
"@
								} else {
@"

$ExNum. $( [String]::Format( $loc.Example, $ExNum ) )
"@
								};
@"

		$($_.code)
"@
							};
						};
						if ( $Help.relatedLinks ) {
@"

##### $( $loc.RelatedLinks )

"@
							$Help.relatedLinks.navigationLink `
							| ? { $_.uri } `
							| % {
								# обрабатываем ссылки на online версию справки
								if ( $_.uri -match $reOnlineHelpLinkCheck ) {
@"
- [$( & { if ( $_.LinkText ) { $_.LinkText } else { $( $loc.OnlineHelp ) } } )]($( $_.uri ))
"@
								} else {
									Write-Warning `
										-Message @"
$( [String]::Format( $loc.WarningLinkError, $FunctionInfo.Name ) )

	$( $_.uri )
	
"@ `
									;
								};
							};
							$Help.relatedLinks.navigationLink `
							| ? { -not $_.uri } `
							| % { $_.LinkText } `
							| % {
								# обрабатываем прочие ссылки
								$Link = `
									$_ `
									| Expand-Definitions `
								;
@"
- $Link
"@
							};
						};
					};
				};
				$ReadMeContent;
			};
		};
		$GetReadmeStatus.level--;
		if ( -not $GetReadmeStatus.level ) {
			Get-EndReference;
		};
	}
}

Function Set-Readme {
	<#
		.Synopsis
			Генерирует readme файл с MarkDown разметкой по данным модуля и комментариям к его функциям. 
			Файл предназначен, в частности, для размещения в репозиториях github.
		.Description
			Генерирует readme файл с MarkDown разметкой по данным модуля и комментариям к его функциям. 
			Файл предназначен, в частности, для размещения в репозиториях github.
			В дополнение к функционалу Get-Readme сохраняет результат в файл, определённый параметра
			`Path`.
		.Functionality
			Readme
		.Role
			Everyone
		.Notes
		.Inputs
			System.Management.Automation.PSModuleInfo.
			Описатели модулей, для которых будет сгенерирован readme.md. 
			Получены описатели могут быть через Get-Module.
		.Inputs
			System.Management.Automation.ExternalScriptInfo.
			Описатели сценариев, для которых будет сгенерирован readme.md. 
		.Inputs
			System.Management.Automation.CmdletInfo.
			Описатели командлет, для которых будет сгенерирован readme.md. 
			Получены описатели могут быть через Get-Command.
		.Inputs
			System.Management.Automation.FunctionInfo.
			Описатели функций, для которых будет сгенерирован readme.md. 
			Получены описатели могут быть через Get-Command.
		.Link
			Get-Readme
		.Link
			[MarkDown]: <http://daringfireball.net/projects/markdown/syntax> "MarkDown (md) Syntax"
		.Link
			about_comment_based_help
		.Link
			[Написание справки для командлетов](http://go.microsoft.com/fwlink/?LinkID=123415)
		.Link
			http://github.com/IT-Service/ITG.Readme#Set-Readme
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | Set-Readme;
			Генерация readme.md файла для модуля `ITG.Yandex.DnsServer` 
			в каталоге модуля.
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | Set-Readme -ReferencedModules @( 'ITG.Yandex', 'ITG.Utils', 'ITG.WinAPI.UrlMon', 'ITG.WinAPI.User32' | Get-Module )
			Генерация readme.md файла для модуля `ITG.Yandex.DnsServer` 
			в каталоге модуля `ITG.Yandex.DnsServer`, при этом все упоминания
			функций модулей `ITG.Yandex`, `ITG.Utils`, `ITG.WinAPI.UrlMon`,
			`ITG.WinAPI.User32` так же будут заменены перекрёстными ссылками
			на readme.md файлы указанных модулей.
	#>
	
	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		[Alias('Module')]
		$ModuleInfo
	,
		# Описатель внешнего сценария
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ExternalScriptInfo'
		)]
		[System.Management.Automation.ExternalScriptInfo]
		$ExternalScriptInfo
	,
		# Описатель функции
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='FunctionInfo'
		)]
		[System.Management.Automation.FunctionInfo]
		$FunctionInfo
	,
		# культура, для которой генерировать данные, на данный момент параметр задавать не следует.
		[Parameter(
			Mandatory=$false
		)]
		[System.Globalization.CultureInfo]
		$UICulture = ( Get-Culture )
	,
		# Путь для readme файла. По умолчанию - `readme.md` в каталоге модуля
		[Parameter(
			ParameterSetName='ModuleInfo'
			, Mandatory=$false
		)]
		[String]
        [Alias('Path')]
		$PSPath = ''
	,
		# Генерировать только краткое описание
		[switch]
		[Alias('Short')]
		$ShortDescription
	,
		# Перечень модулей, упоминания функций которых будут заменены на ссылки
		[Parameter(
			Mandatory=$false
		)]
		[PSModuleInfo[]]
		$ReferencedModules = @()
	,
		# Правила для обработки readme регулярными выражениями
		[Parameter(
			Mandatory=$false
		)]
		[Array]
		$TranslateRules = @()
	,
		# Передавать полученный по конвейеру описатель дальше
		[switch]
		$PassThru
	)

	process {
        if ( -not $PSPath ) {
            $PSPath = `
	            $ModuleInfo.ModuleBase `
	            | Join-Path -ChildPath 'readme.md' `
            ;
        };
		$null = $PSBoundParameters.Remove( 'PSPath' );
		$null = $PSBoundParameters.Remove( 'PassThru' );

		switch ( $PsCmdlet.ParameterSetName ) {
			'ModuleInfo' {
				( Get-Readme @PSBoundParameters ) `
				, (
@"

---------------------------------------

$( [String]::Format( $loc.GeneratorAbout, 'ITG.Readme', 'http://github.com/IT-Service/ITG.Readme' ) )
"@ `
				) `
				| Out-String `
				| Set-Content `
					-LiteralPath $PSPath `
					-Encoding 'UTF8' `
					-Force `
				;
			}
			'ExternalScriptInfo' {
			}
			default {
			};
		};
        
        if ( $PassThru ) { return $input };
	}
}

Function Get-AboutModule {
	<#
		.Synopsis
			Генерирует содержимое файла `about_$(ModuleInfo.Name).txt` с MarkDown разметкой
			по данным модуля и комментариям к его функциям. 
		.Description
			Генерирует содержимое файла `about_$(ModuleInfo.Name).txt` с MarkDown разметкой
			по данным модуля и комментариям к его функциям.
            Для сохранения в файл используйте Set-AboutModule.
		.Functionality
			Readme
		.Role
			Everyone
		.Notes
		.Inputs
			System.Management.Automation.PSModuleInfo.
			Описатели модулей, для которых будет сгенерирован about.txt. 
			Получены описатели могут быть через Get-Module.
		.Outputs
			String.
			Содержимое about.txt.
		.Link
			[MarkDown]: <http://daringfireball.net/projects/markdown/syntax> "MarkDown (md) Syntax"
		.Link
			about_comment_based_help
		.Link
			[Написание справки для командлетов](http://go.microsoft.com/fwlink/?LinkID=123415)
		.Link
			http://github.com/IT-Service/ITG.Readme#Get-AboutModule
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | Get-AboutModule;
			Генерация содержимого about.txt файла для модуля `ITG.Yandex.DnsServer`.
	#>
	
	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		[Alias('Module')]
		$ModuleInfo
	,
		# культура, для которой генерировать данные, на данный момент параметр задавать не следует.
		[Parameter(
			Mandatory=$false
		)]
		[System.Globalization.CultureInfo]
		$UICulture = ( Get-Culture )
	,
		# Перечень модулей, упоминания функций которых будут заменены на ссылки
		[Parameter(
			Mandatory=$false
		)]
		[PSModuleInfo[]]
		$ReferencedModules = @()
	)

	process {
		switch ( $PsCmdlet.ParameterSetName ) {
			'ModuleInfo' {
                return Get-Readme `
                    @PSBoundParameters `
                    -ShortDescription `
                ;
			}
		}
	}
}

Function Set-AboutModule {
	<#
		.Synopsis
			Генерирует файл `about_$(ModuleInfo.Name).txt` с MarkDown разметкой
			по данным модуля и комментариям к его функциям.
		.Description
			Генерирует файл `about_$(ModuleInfo.Name).txt` с MarkDown разметкой
			по данным модуля и комментариям к его функциям в подкаталоге указанной
			культуры в каталоге модуля или в соответствии с указанным значением
			параметра `Path`.
		.Functionality
			Readme
		.Role
			Everyone
		.Notes
		.Inputs
			System.Management.Automation.PSModuleInfo.
			Описатели модулей, для которых будет сгенерирован readme.md. 
			Получены описатели могут быть через Get-Module.
		.Link
			Get-AboutModule
		.Link
			[MarkDown]: <http://daringfireball.net/projects/markdown/syntax> "MarkDown (md) Syntax"
		.Link
			about_comment_based_help
		.Link
			[Написание справки для командлетов](http://go.microsoft.com/fwlink/?LinkID=123415)
		.Link
			http://github.com/IT-Service/ITG.Readme#Set-AboutModule
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | Set-AboutModule;
			Генерация `about_ITG.Yandex.DnsServer.txt` файла для модуля `ITG.Yandex.DnsServer` 
			в подкаталоге текущей культуры в каталоге модуля.
	#>
	
	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		[Alias('Module')]
		$ModuleInfo
	,
		# культура, для которой генерировать данные, на данный момент параметр задавать не следует.
		[Parameter(
			Mandatory=$false
		)]
		[System.Globalization.CultureInfo]
		$UICulture = ( Get-Culture )
	,
		# Путь для about.txt файла. По умолчанию - в подкаталоге указанной культуры.
		[Parameter(
			ParameterSetName='ModuleInfo'
			, Mandatory=$false
		)]
		[String]
        [Alias('Path')]
		$PSPath = ''
	,
		# Перечень модулей, упоминания функций которых будут заменены на ссылки
		[Parameter(
			Mandatory=$false
		)]
		[PSModuleInfo[]]
		$ReferencedModules = @()
	,
		# Передавать полученный по конвейеру описатель дальше
		[switch]
		$PassThru
	)

	process {
        if ( -not $PSPath ) {
            $PSPath = `
	            $ModuleInfo.ModuleBase `
	            | Join-Path -ChildPath ( $UICulture.Name ) `
	            | Join-Path -ChildPath "about_$( $ModuleInfo.Name ).txt" `
            ;
        };
		$null = $PSBoundParameters.Remove( 'PSPath' );
		$null = $PSBoundParameters.Remove( 'PassThru' );

		switch ( $PsCmdlet.ParameterSetName ) {
			'ModuleInfo' {
				( Get-AboutModule @PSBoundParameters ) `
				, (
@"

---------------------------------------

$( [String]::Format( $loc.GeneratorAbout, 'ITG.Readme', 'http://github.com/IT-Service/ITG.Readme' ) )
"@ `
				) `
				| Out-String `
				| Set-Content `
					-LiteralPath $PSPath `
					-Encoding 'UTF8' `
					-Force `
				;
			}
		};
        
        if ( $PassThru ) { return $input };
	}
}

Filter Split-Para {
	<#
		.Synopsis
			Делит переданный текст на абзацы по правилам MarkDown. В качестве границы
			абзацев - пустая строка. Текст в пределах абзаца объединяет в одну строку.
	#>
	param (
		[Parameter(
			Mandatory = $true
			, ValueFromPipeline = $true
		)]
		[String]
		[AllowEmptyString()]
		[Alias('Text')]
		$InputObject
	)
	
	$InputObject -split '(?:[ \t]*\r?\n[ \t]*){2,}' `
	| % {
		$_ -replace '(?:[ \t]*\r?\n[ \t]*)', ' ' `
		 	-replace '[ \t]+$', '' `
		;
	};
}

$HelpXMLNS = @{
	msh='http://msh';
	maml='http://schemas.microsoft.com/maml/2004/10';
	command='http://schemas.microsoft.com/maml/dev/command/2004/10';
	dev='http://schemas.microsoft.com/maml/dev/2004/10';
	MSHelp='http://msdn.microsoft.com/mshelp';
	HelpInfo='http://schemas.microsoft.com/powershell/help/2010/05';
};

Function DoTextElement( $HelpContent, $Root, $Prefix, $El, $NS, $Txt ) {
	if ( $Txt ) {
		$null = $Root.AppendChild(
			$HelpContent.CreateElement( $Prefix, $El, $NS )
		).AppendChild(
			$HelpContent.CreateTextNode( $Txt )
		);
	};
};

Function DoNameElement( $HelpContent, $Root, $Txt ) {
	DoTextElement $HelpContent $Root 'maml' 'name' ( $HelpXMLNS.maml ) $Txt;
};

Function DoCustomParaElement( $HelpContent, $Root, $El, $ParaEl, $Description ) {
	if ( $Description ) {
		$DescriptionEl = $Root.AppendChild(
			$HelpContent.CreateElement( 'maml', $El, ( $HelpXMLNS.maml ) )
		);
		$Description `
		| Split-Para `
		| % {
			DoTextElement $HelpContent $DescriptionEl 'maml' $ParaEl ( $HelpXMLNS.maml ) $_;
		};
	};
};

Function DoParaElement( $HelpContent, $Root, $El, $Description ) {
	DoCustomParaElement $HelpContent $Root $El 'para' $Description;
};

Function DoDescription( $HelpContent, $Root, $Description ) {
	DoParaElement $HelpContent $Root 'description' $Description;
};

Function DoValuesList( $HelpContent, $Root, $Help, $ListId, $ListItemId ) {
	if ( $Help.$ListId ) {
		$List = $Root.AppendChild(
			$HelpContent.CreateElement( '', $ListId, ( $HelpXMLNS.command ) )
		);
		$Help.$ListId.$ListItemId `
		| % {
			$Txt = @( $_.type.name -split '\r?\n' );
			$TypeName = $Txt[0];

			$null = $List.AppendChild(
				( $ItemEl = $HelpContent.CreateElement( '', $ListItemId, ( $HelpXMLNS.command ) ) )
			).AppendChild(
				( $DevType = $HelpContent.CreateElement( 'dev', 'type', ( $HelpXMLNS.dev ) ) )
			);
			DoTextElement $HelpContent $DevType 'maml' 'name' ( $HelpXMLNS.maml ) $TypeName;
			DoTextElement $HelpContent $DevType 'maml' 'uri' ( $HelpXMLNS.maml ) ( $_.type.uri );

			if ( $_.type.description ) {
				$TypeDescription = $_.type.description | Select-Object -ExpandProperty Text;
			} elseif ( $Txt.Count -gt 1 ) {
				$TypeDescription = $Txt[1..( $Txt.Count-1 )] | Out-String;
			} else {
				$TypeDescription = '';
			};
			DoDescription $HelpContent $DevType $TypeDescription;

			if ( $_.Description ) {
				$TypeDescription = $_.Description | Select-Object -ExpandProperty Text;
			};
			DoDescription $HelpContent $ItemEl $TypeDescription;
		};
	};
};

Function DoParaList( $HelpContent, $Root, $Help, $ListId, $ListItemId ) {
	if ( $Help.$ListId ) {
		$List = $Root.AppendChild(
			$HelpContent.CreateElement( 'maml', $ListId, ( $HelpXMLNS.maml ) )
		);
		$Help.$ListId.$ListItemId `
		| % {
			DoParaElement $HelpContent $List $ListItemId ( $_.Text );
		};
	};
};

Function New-HelpXML {
	<#
		.Synopsis
			Генерирует XML справку для переданного модуля, функции, командлеты.
		.Description
			Генерирует XML справку для переданного модуля, функции, командлеты.
			
			Для генерации / обновления .xml файла справки в каталоге модуля
			используйте Set-HelpXML.
		.Role
			Everyone
		.Inputs
			System.Management.Automation.PSModuleInfo
			Описатели модулей. Именно для них и будет сгенерирована XML справка. 
			Получены описатели могут быть через `Get-Module`.
		.Inputs
			System.Management.Automation.FunctionInfo
			Описатели функций. Именно для них и будет сгенерирована XML справка. 
			Получены описатели могут быть через `Get-Command`.
		.Inputs
			System.Management.Automation.CmdletInfo
			Описатели командлет. Именно для них и будет сгенерирована XML справка. 
			Получены описатели могут быть через `Get-Command`.
		.Outputs
			System.Xml.XmlDocument
			Содержимое XML справки.
		.Link
			about_Comment_Based_Help
		.Link
			about_Updatable_Help
		.Link
			[Creating the Cmdlet Help File](http://msdn.microsoft.com/en-us/library/bb525433.aspx)
		.Link
			http://github.com/IT-Service/ITG.Readme#New-HelpXML
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | New-HelpXML;
			Генерация xml справки для модуля `ITG.Yandex.DnsServer`.
	#>

	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		[Alias('Module')]
		$ModuleInfo
	,
		# Описатель функции
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='FunctionInfo'
		)]
		[System.Management.Automation.FunctionInfo]
		$FunctionInfo
	)

	process {
		trap {
			break;
		};
		switch ( $PsCmdlet.ParameterSetName ) {
			'ModuleInfo' {
				[System.Xml.XmlDocument]$HelpContent = @"
<!-- $( [String]::Format( $loc.GeneratorXmlAbout, 'ITG.Readme', 'http://github.com/IT-Service/ITG.Readme' ) ) -->
<helpItems
	xmlns="$( $HelpXMLNS.msh )"
	xmlns:maml="$( $HelpXMLNS.maml )"
	xmlns:command="$( $HelpXMLNS.command )" 
	xmlns:dev="$( $HelpXMLNS.dev )"
	xmlns:MSHelp="$( $HelpXMLNS.MSHelp )"
	schema="maml"
/>
"@
				if ( $ModuleInfo.ExportedFunctions ) {
					$ModuleInfo.ExportedFunctions.Values `
					| New-HelpXML `
					| % {
						$null = $HelpContent.DocumentElement.AppendChild( $HelpContent.ImportNode( $_.DocumentElement, $true ) );
					};
				};
				return $HelpContent;
			}
			'FunctionInfo' {
				$ModuleManifestPath = Join-Path `
					-Path ( $FunctionInfo.Module.ModuleBase ) `
					-ChildPath "$( $FunctionInfo.Module.Name ).psd1" `
				;
				if ( -not ( Test-Path -LiteralPath $ModuleManifestPath ) ) {
					Write-Error `
						-Message ( [String]::Format( $loc.ErrorModuleManifestPathMessage, $ModuleManifestPath ) ) `
						-Category ResourceUnavailable `
						-CategoryActivity ( $loc.ErrorModuleManifestPathActivity ) `
						-CategoryReason ( $loc.ErrorModuleManifestPathReason ) `
						-CategoryTargetName ( $FunctionInfo.Module.Name ) `
						-TargetObject ( $FunctionInfo.Module ) `
						-RecommendedAction ( $loc.ErrorModuleManifestPathRecommendedAction ) `
					;
					return;
				};
				$Module = Invoke-Expression ( ( Get-Content -LiteralPath $ModuleManifestPath -ReadCount 0 ) -join "`r`n" ) ;
				
				[xml]$HelpContent = @"
<command
	xmlns:msh="$( $HelpXMLNS.msh )"
	xmlns:maml="$( $HelpXMLNS.maml )"
	xmlns="$( $HelpXMLNS.command )" 
	xmlns:dev="$( $HelpXMLNS.dev )"
	xmlns:MSHelp="$( $HelpXMLNS.MSHelp )"
/>
"@
				$Command = $HelpContent.DocumentElement;
				
				$Details = $Command.AppendChild(
					$HelpContent.CreateElement( '', 'details', ( $HelpXMLNS.command ) )
				);
				DoTextElement $HelpContent $Details '' 'name' ( $HelpXMLNS.command ) ( $FunctionInfo.Name );

				$NameParts = @( $FunctionInfo.Name -split '-' );
				if ( $NameParts.Count -eq 2 ) {
					DoTextElement $HelpContent $Details '' 'verb' ( $HelpXMLNS.command ) ( $NameParts[0] );
					DoTextElement $HelpContent $Details '' 'noun' ( $HelpXMLNS.command ) ( $NameParts[1] );
				};

				$Help = $( $FunctionInfo | Get-Help -Full );

				DoDescription $HelpContent $Details ( $Help.Synopsis );
				DoParaElement $HelpContent $Details 'copyright' ( $Module.Copyright );
				DoTextElement $HelpContent $Details 'dev' 'version' ( $HelpXMLNS.dev ) ( $Module.ModuleVersion );
				DoTextElement $HelpContent $Command 'maml' 'component' ( $HelpXMLNS.maml ) ( $Help.Component );
				DoTextElement $HelpContent $Command 'maml' 'functionality' ( $HelpXMLNS.maml ) ( $Help.Functionality );
				DoTextElement $HelpContent $Command 'maml' 'role' ( $HelpXMLNS.maml ) ( $Help.Role );
				DoDescription $HelpContent $Command ( $Help.Description | Select-Object -ExpandProperty Text );

				if ( $Help.Syntax ) {
					$null = $Command.AppendChild(
						( $Syntax = $HelpContent.CreateElement( '', 'syntax', ( $HelpXMLNS.command ) ) )
					);
					$Help.Syntax.SyntaxItem `
					| % {
						$SyntaxItem = $Syntax.AppendChild(
							$HelpContent.CreateElement( '', 'syntaxItem', ( $HelpXMLNS.command ) )
						);
						DoNameElement $HelpContent $SyntaxItem ( $FunctionInfo.Name );
						
						$_.Parameter `
						| % {
							$Parameter = $SyntaxItem.AppendChild(
								$HelpContent.CreateElement( '', 'parameter', ( $HelpXMLNS.command ) )
							);
							DoNameElement $HelpContent $Parameter ( $_.Name );
							$Parameter.SetAttribute( 'required', ( $_.Required ) );
							$Parameter.SetAttribute( 'position', ( $_.Position ) );
							$Parameter.SetAttribute( 'pipelineInput', ( $_.PipelineInput ) );
							if ( $_.variableLength ) {
								$Parameter.SetAttribute( 'variableLength', ( $_.variableLength ) );
							};
							if ( $_.globbing ) {
								$Parameter.SetAttribute( 'globbing', ( $_.globbing ) );
							};

							if ( $_.parameterValue ) {
								$null = $Parameter.AppendChild(
									( $ParameterValue = $HelpContent.CreateElement( '', 'parameterValue', ( $HelpXMLNS.command ) ) )
								).AppendChild(
									$HelpContent.CreateTextNode( ( $_.parameterValue ) )
								);
								$ParameterValue.SetAttribute( 'required', ( $_.Required ) );
								if ( $_.variableLength ) {
									$ParameterValue.SetAttribute( 'variableLength', ( $_.variableLength ) );
								};
							};
						};
					};
				};

				if ( $Help.Parameters ) {
					$Parameters = $Command.AppendChild(
						$HelpContent.CreateElement( '', 'parameters', ( $HelpXMLNS.command ) )
					);
					$Help.Parameters.Parameter `
					| % {
						$Parameter = $Parameters.AppendChild(
							$HelpContent.CreateElement( '', 'parameter', ( $HelpXMLNS.command ) )
						);
						DoNameElement $HelpContent $Parameter ( $_.Name );

						$Parameter.SetAttribute( 'required', ( $_.Required ) );
						$Parameter.SetAttribute( 'position', ( $_.Position ) );
						$Parameter.SetAttribute( 'pipelineInput', ( $_.PipelineInput ) );
						if ( $_.variableLength ) {
							$Parameter.SetAttribute( 'variableLength', ( $_.variableLength ) );
						};
						if ( $_.globbing ) {
							$Parameter.SetAttribute( 'globbing', ( $_.globbing ) );
						};

						DoDescription $HelpContent $Parameter ( $_.Description | Select-Object -ExpandProperty Text );
						
						if ( $_.parameterValue ) {
							$null = $Parameter.AppendChild(
								( $ParameterValue = $HelpContent.CreateElement( '', 'parameterValue', ( $HelpXMLNS.command ) ) )
							).AppendChild(
								$HelpContent.CreateTextNode( ( $_.parameterValue ) )
							);
							$ParameterValue.SetAttribute( 'required', $true );
							if ( $_.variableLength ) {
								$ParameterValue.SetAttribute( 'variableLength', ( $_.variableLength ) );
							};
						};
						
						DoTextElement $HelpContent $Parameter '' 'defaultValue' ( $HelpXMLNS.command ) ( $_.defaultValue );
						
						if ( $_.possibleValues ) {
							$PossibleValues = $Command.AppendChild(
								$HelpContent.CreateElement( 'dev', 'possibleValues', ( $HelpXMLNS.dev ) )
							);
							$_.possibleValues.possibleValue `
							| % {
								$PossibleValue = $PossibleValues.AppendChild(
									$HelpContent.CreateElement( 'dev', 'possibleValue', ( $HelpXMLNS.dev ) )
								);
								DoTextElement $HelpContent $PossibleValue 'dev' 'value' ( $HelpXMLNS.dev ) ( $_.value );
								DoDescription $HelpContent $PossibleValue ( $_.Description | Select-Object -ExpandProperty Text );
							};
						};
					};
				};

				DoValuesList $HelpContent $Command $Help 'inputTypes' 'inputType';
				DoValuesList $HelpContent $Command $Help 'returnValues' 'returnValue';
				DoParaList $HelpContent $Command $Help 'alertSet' 'alert';

				if ( $Help.Examples ) {
					$Examples = $Command.AppendChild(
						$HelpContent.CreateElement( '', 'examples', ( $HelpXMLNS.command ) )
					);
					$Help.Examples.Example `
					| % {
						$Example = $Examples.AppendChild(
							$HelpContent.CreateElement( '', 'example', ( $HelpXMLNS.command ) )
						);
						DoTextElement $HelpContent $Example 'maml' 'title' ( $HelpXMLNS.maml ) ( $_.title );
						$Prompt = $Example.AppendChild(
							$HelpContent.CreateElement( 'maml', 'introduction', ( $HelpXMLNS.maml ) )
						);
						$_.introduction `
						| % { $_.Text -replace '^\s+|\s+$', '' } `
						| Out-String `
						| Split-Para `
						| % {
							DoTextElement $HelpContent $Prompt 'maml' 'paragraph' ( $HelpXMLNS.maml ) $_;
						};
						DoTextElement $HelpContent $Example 'dev' 'code' ( $HelpXMLNS.dev ) ( $_.code );
						DoParaElement $HelpContent $Example 'remarks' (
							$_.remarks `
							| % { $_.Text -replace '(?m)^\s+|\s+$', '' } `
							| Out-String `
						);
					};
				};

				if ( $Help.relatedLinks ) {
					$ListEl = $Command.AppendChild(
						$HelpContent.CreateElement( 'maml', 'relatedLinks', ( $HelpXMLNS.maml ) )
					);
					$Help.relatedLinks.navigationLink `
					| % {
						$ListItemEl = $ListEl.AppendChild(
							$HelpContent.CreateElement( 'maml', 'navigationLink', ( $HelpXMLNS.maml ) )
						);
						DoTextElement $HelpContent $ListItemEl 'maml' 'uri' ( $HelpXMLNS.maml ) ( $_.uri );
						DoTextElement $HelpContent $ListItemEl 'maml' 'linkText' ( $HelpXMLNS.maml ) ( $_.linkText );
					};
				};

				return $HelpContent;
			};
		};
	};
}

Function Get-HelpXML {
	<#
		.Synopsis
			Возващает XML содержимое xml файла справки для переданного модуля.
		.Description
			Возващает XML содержимое xml файла справки для переданного модуля.
		.Role
			Everyone
		.Inputs
			System.Management.Automation.PSModuleInfo
			Описатели модулей. Именно для них и будет сгенерирована XML справка. 
			Получены описатели могут быть через `Get-Module`.
		.Outputs
			System.Xml.XmlDocument
			Содержимое XML справки.
		.Link
			about_Updatable_Help
		.Link
			[Creating the Cmdlet Help File](http://msdn.microsoft.com/en-us/library/bb525433.aspx)
		.Link
			http://github.com/IT-Service/ITG.Readme#Get-HelpXML
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | Get-HelpXML;
			Возвращает содержимое xml файла справки для модуля `ITG.Yandex.DnsServer` 
			в виде XML документа.
	#>
	
	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		[Alias('Module')]
		$ModuleInfo
	,
		# культура, для которой вернуть данные, на данный момент параметр задавать не следует.
		[Parameter(
			Mandatory=$false
		)]
		[System.Globalization.CultureInfo]
		$UICulture = ( Get-Culture )
	,
		# Путь для xml файла справки
		[Parameter(
			ParameterSetName='ModuleInfo'
			, Mandatory=$false
		)]
		[String]
        [Alias('Path')]
		$PSPath = ''
	)

	process {
		trap {
			break;
		};
		switch ( $PsCmdlet.ParameterSetName ) {
			'ModuleInfo' {
                if ( -not $PSPath ) {
                    $PSPath = `
	                    $ModuleInfo.ModuleBase `
	                    | Join-Path -ChildPath ( $UICulture.Name ) `
	                    | Join-Path -ChildPath "$( $ModuleInfo.Name )-help.xml" `
                    ;
                };
				if ( Test-Path $PSPath ) {
					return ( [xml](
						Get-Content `
							-LiteralPath $PSPath `
							-ReadCount 0 `
					));
				} else {
					return [xml] @"
<!-- $( [String]::Format( $loc.GeneratorXmlAbout, 'ITG.Readme', 'http://github.com/IT-Service/ITG.Readme' ) ) -->
<helpItems
	xmlns="$( $HelpXMLNS.msh )"
	xmlns:maml="$( $HelpXMLNS.maml )"
	xmlns:command="$( $HelpXMLNS.command )" 
	xmlns:dev="$( $HelpXMLNS.dev )"
	xmlns:MSHelp="$( $HelpXMLNS.MSHelp )"
	schema="maml"
/>
"@
				};
			}
		};
	}
}

Function Set-HelpXML {
	<#
		.Synopsis
			Генерирует XML файл справки для переданного модуля, функции, командлеты.
		.Description
			Генерирует XML файл справки для переданного модуля, функции, командлеты.
			
			Кроме того, данная
			функция создаст XML файл справки в каталоге модуля (точнее - в
			подкаталоге культуры, как того и требуют командлеты PowerShell, в
			частности - `Get-Help`).
		.Notes
			Необходимо дополнительное тестирование на PowerShell 3.
		.Role
			Everyone
		.Inputs
			System.Management.Automation.PSModuleInfo
			Описатели модулей. Именно для них и будет сгенерирована XML справка. 
			Получены описатели могут быть через `Get-Module`.
		.Inputs
			System.Management.Automation.FunctionInfo
			Описатели функций. Именно для них и будет сгенерирована XML справка. 
			Получены описатели могут быть через `Get-Command`.
		.Inputs
			System.Management.Automation.CmdletInfo
			Описатели командлет. Именно для них и будет сгенерирована XML справка. 
			Получены описатели могут быть через `Get-Command`.
		.Link
			about_Updatable_Help
		.Link
			[Creating the Cmdlet Help File](http://msdn.microsoft.com/en-us/library/bb525433.aspx)
		.Link
			http://github.com/IT-Service/ITG.Readme#Set-HelpXML
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | Set-HelpXML;
			Генерация xml файла справки для модуля `ITG.Yandex.DnsServer` 
			в каталоге модуля.
	#>
	
	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		[Alias('Module')]
		$ModuleInfo
	,
		# Описатель функции
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='FunctionInfo'
		)]
		[System.Management.Automation.FunctionInfo]
		$FunctionInfo
	,
		# культура, для которой генерировать данные, на данный момент параметр задавать не следует.
		[Parameter(
			Mandatory=$false
		)]
		[System.Globalization.CultureInfo]
		$UICulture = ( Get-Culture )
	,
		# Путь для xml файла справки
		[Parameter(
			ParameterSetName='ModuleInfo'
			, Mandatory=$false
		)]
		[String]
        [Alias('Path')]
		$PSPath = ''
	,
		# обновлять файл модуля - добавлять в файл модуля в комментарии к функциям модуля 
		# записи типа `.ExternalHelp ITG.Readme-help.xml`
		[Parameter(
			ParameterSetName='ModuleInfo'
		)]
		[switch]
		$UpdateModule
	,
		# генерировать / обновлять или нет .cab файл
		[Parameter(
			ParameterSetName='ModuleInfo'
		)]
		[switch]
		$Cab
	,
		# Путь к .cab файлу
		[Parameter(
			ParameterSetName='ModuleInfo'
			, Mandatory=$false
		)]
		[String]
        [Alias('$CabPath')]
		$PSCabPath = ''
	,
		# Передавать полученный по конвейеру описатель дальше
		[switch]
		$PassThru
	)

	process {
		trap {
			break;
		};
		switch ( $PsCmdlet.ParameterSetName ) {
			'ModuleInfo' {
                if ( -not $PSPath ) {
                    $PSPath = `
	                    $ModuleInfo.ModuleBase `
	                    | Join-Path -ChildPath ( $UICulture.Name ) `
	                    | Join-Path -ChildPath "$( $ModuleInfo.Name )-help.xml" `
                    ;
                };
                if ( -not $PSCabPath ) {
                    $PSCabPath = `
	                    $ModuleInfo.ModuleBase `
	                    | Join-Path -ChildPath 'help.cab' `
	                    | Join-Path -ChildPath "$( $ModuleInfo.Name )_$( $ModuleInfo.GUID )_$( $UICulture )_HelpContent.cab" `
                    ;
                };

				[System.Xml.XmlDocument]$HelpContent = New-HelpXML -ModuleInfo $ModuleInfo;

				$Dir = Split-Path -Path ( $PSPath ) -Parent;
				if ( -not ( Test-Path -LiteralPath $Dir ) ) {
					$null = New-Item -Path $Dir -ItemType Directory;
				};
				
				$Writer = [System.Xml.XmlWriter]::Create(
					$PSPath `
					, ( New-Object `
						-TypeName System.Xml.XmlWriterSettings `
						-Property @{
							Indent = $true;
							OmitXmlDeclaration = $false;
							NamespaceHandling = [System.Xml.NamespaceHandling]::OmitDuplicates;
							NewLineOnAttributes = $false;
							CloseOutput = $true;
							IndentChars = "`t";
						} `
					) `
				);
				$HelpContent.WriteTo( $Writer );
				$Writer.Close();

				if ( $Cab ) {
					$CabDir = Split-Path -Path ( $PSCabPath ) -Parent;
					if ( -not ( Test-Path -LiteralPath $CabDir ) ) {
						$null = New-Item -Path $CabDir -ItemType Directory;
					};
					$MakeCabProcess = Start-Process `
						-FilePath 'makecab' `
						-ArgumentList "`"$( $PSPath )`"", "`"$( $PSCabPath )`"" `
						-NoNewWindow `
						-Wait `
						-PassThru `
					;
					if ( $MakeCabProcess.ExitCode ) {
						Write-Error `
							-Message ( [String]::Format( $loc.ErrorMakeCabMessage, $MakeCabProcess.ExitCode ) ) `
						;
					};
				};

				if ( $UpdateModule ) {
					$reFuncHeaders = 
						'(?m)' `
						, '(?<=^(Function|Filter)\s+(' `
						, (
							(
								$ModuleInfo.ExportedFunctions.Values `
								| % { $_.Name } `
							) `
							-join '|' `
						) `
						, ')\s*\{)(\s*$)?' `
						-join '' `
					;
					$ModulePath = $ModuleInfo.Path;
					( Get-Content `
						-LiteralPath $ModulePath `
						-ReadCount 0 `
					) `
					-join "`r`n" `
					-replace `
						$reFuncHeaders `
						, "`r`n#`t.ExternalHelp $HelpXMLFileName`r`n" `
					| Set-Content `
						-LiteralPath $ModulePath `
						-Encoding 'UTF8' `
						-Force `
					;
				};
			}
		};
        
        if ( $PassThru ) { return $input };
	}
}

Function New-HelpInfo {
	<#
		.Synopsis
			Генерирует HelpInfo XML для переданного модуля.
		.Description
			Генерирует HelpInfo XML для переданного модуля, без записи в файл. 
			HelpInfo.XML по сути является манифестом для xml справки модуля.
		.Notes
			Для записи HelpInfo.xml файла используйте Set-HelpInfo.
		.Role
			Everyone
		.Inputs
			System.Management.Automation.PSModuleInfo
			Описатели модулей. Именно для них и будет сгенерирован манифест XML справки (HelpInfo.xml). 
			Получены описатели могут быть через `Get-Module`.
		.Outputs
			System.Xml.XmlDocument
			Содержимое XML манифеста (HelpInfo.xml) справки.
		.Link
			about_Updatable_Help
		.Link
			Set-HelpInfo
		.Link
			http://github.com/IT-Service/ITG.Readme#New-HelpInfo
		.Link
			[HelpInfo XML Sample File](http://msdn.microsoft.com/en-us/library/windows/desktop/hh852750.aspx)
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | New-HelpInfo;
			Генерация xml манифеста справки для модуля `ITG.Yandex.DnsServer`.
	#>
	
	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		[Alias('Module')]
		$ModuleInfo
	,
		# "Заготовка" для `HelpContentURI` - функционал (блок), вычисляющий URI для .cab файлов справки
		[Parameter(
			Mandatory=$false
		)]
		[ScriptBlock]
		$HelpContentUriTemplate = $GitHubHelpContentURI
	,
		# Ссылка для загрузки обновляемой справки. Смотрите about_Updatable_Help.
		# Значение по умолчанию - url к репозиторию проекта на github.
		[Parameter(
			ParameterSetName='ModuleInfo'
			, Mandatory=$false
		)]
		[System.Uri]
		$HelpContentUri = ( & $HelpContentUriTemplate )
	)

	process {
		trap {
			break;
		};
		switch ( $PsCmdlet.ParameterSetName ) {
			'ModuleInfo' {
				$HelpInfoContent = New-Object -TypeName System.Xml.XmlDocument;
				$HelpInfo = $HelpInfoContent.AppendChild(
					$HelpInfoContent.CreateElement( '', 'HelpInfo', ( $HelpXMLNS.HelpInfo ) )
				);
				DoTextElement $HelpInfoContent $HelpInfo '' 'HelpContentURI' ( $HelpXMLNS.HelpInfo ) (
					$HelpContentUri
				);
				$SupportedUICultures = $HelpInfo.AppendChild(
					$HelpInfoContent.CreateElement( '', 'SupportedUICultures', ( $HelpXMLNS.HelpInfo ) )
				);
				Get-Culture `
				| % {
					$UICulture = $SupportedUICultures.AppendChild(
						$HelpInfoContent.CreateElement( '', 'UICulture', ( $HelpXMLNS.HelpInfo ) )
					);
					DoTextElement $HelpInfoContent $UICulture '' 'UICultureName' ( $HelpXMLNS.HelpInfo ) ( $_.Name );
					DoTextElement $HelpInfoContent $UICulture '' 'UICultureVersion' ( $HelpXMLNS.HelpInfo ) ( $ModuleInfo.Version );
				};
				return $HelpInfoContent;
			}
		};
	}
}

Function Get-HelpInfo {
	<#
		.Synopsis
			Возвращает HelpInfo.xml (как xml) для указанного модуля.
		.Description
			Вычисляет наименование и положение HelpInfo.xml файла для указанного модуля
			и возвращает его содержимое. Если файл не обнаружен - возвращает пустую
			xml "заготовку" HelpInfo.xml, но валидную.
		.Role
			Everyone
		.Inputs
			System.Management.Automation.PSModuleInfo
			Описатели модулей. Именно для них и будет возвращён манифест XML справки (HelpInfo.xml). 
			Получены описатели могут быть через `Get-Module`.
		.Outputs
			System.Xml.XmlDocument
			Содержимое XML манифеста (HelpInfo.xml) справки.
		.Link
			about_Updatable_Help
		.Link
			Set-HelpInfo
		.Link
			New-HelpInfo
		.Link
			http://github.com/IT-Service/ITG.Readme#Get-HelpInfo
		.Link
			[How to Name a HelpInfo XML File](http://msdn.microsoft.com/en-us/library/windows/desktop/hh852748.aspx)
		.Link
			[HelpInfo XML Sample File](http://msdn.microsoft.com/en-us/library/windows/desktop/hh852750.aspx)
		.Example
			Get-Module 'ITG.Yandex.DnsServer' | Get-HelpInfo;
			Возвращает xml манифест справки для модуля `ITG.Yandex.DnsServer`.
	#>
	
	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		[Alias('Module')]
		$ModuleInfo
	)

	process {
		trap {
			break;
		};
		switch ( $PsCmdlet.ParameterSetName ) {
			'ModuleInfo' {
				$HelpInfoPath = ( Join-Path `
					-Path ( Split-Path -Path ( $ModuleInfo.Path ) -Parent ) `
					-ChildPath "$( $ModuleInfo.Name )_$( $ModuleInfo.GUID )_HelpInfo.xml" `
				);
				if ( Test-Path $HelpInfoPath ) {
					return ( [xml](
						Get-Content `
							-LiteralPath $HelpInfoPath `
							-ReadCount 0 `
					));
				} else {
					return [xml] @"
<HelpInfo xmlns="$( $HelpXMLNS.HelpInfo )">
	<SupportedUICultures/>
</HelpInfo>
"@
				};
			}
		};
	}
}

Function Set-HelpInfo {
	<#
		.Synopsis
			Генерирует HelpInfo XML для указанного модуля.
		.Description
			Генерирует HelpInfo XML для переданного модуля, и
			вносит изменения (в части текущей культуры) в существующий файл
			HelpInfo.xml в каталоге модуля, либо создаёт новый файл.
		.Role
			Everyone
		.Inputs
			System.Management.Automation.PSModuleInfo
			Описатели модулей. Именно для них и будет сгенерирован манифест XML справки (HelpInfo.xml). 
			Получены описатели могут быть через `Get-Module`.
		.Outputs
			None.
		.Link
			about_Updatable_Help
		.Link
			http://github.com/IT-Service/ITG.Readme#Set-HelpInfo
		.Link
			[HelpInfo XML Sample File](http://msdn.microsoft.com/en-us/library/windows/desktop/hh852750.aspx)
		.Example
			Set-HelpInfo -ModuleInfo ( Get-Module 'ITG.Yandex.DnsServer' );
			Создание / модификация HelpInfo.xml файла для модуля `ITG.Yandex.DnsServer` в каталоге модуля.
	#>
	
	[CmdletBinding(
		DefaultParametersetName='ModuleInfo'
	)]

	param (
		# Описатель модуля
		[Parameter(
			Mandatory=$true
			, Position=0
			, ValueFromPipeline=$true
			, ParameterSetName='ModuleInfo'
		)]
		[PSModuleInfo]
		[Alias('Module')]
		$ModuleInfo
	,
		# Ссылка для загрузки обновляемой справки. Смотрите about_Updatable_Help.
		# Значение по умолчанию - url к репозиторию проекта на github.
		[Parameter(
			ParameterSetName='ModuleInfo'
			, Mandatory=$false
		)]
		[System.Uri]
		$HelpContentUri = $null
	,
		# Обновлять или нет манифест модуля. Речь идёт о создании / обновлении параметра 
		# HelpInfoURI в манифесте, который как раз и должен указывать на HelpInfo.xml файл
		[Parameter(
			ParameterSetName='ModuleInfo'
		)]
		[switch]
		$UpdateManifest
	,
		# Используется только совместно
		# с `UpdateManifest`. Значение по умолчанию - url к репозиторию проекта на github.
		[Parameter(
			ParameterSetName='ModuleInfo'
			, Mandatory=$false
		)]
		[System.Uri]
		$HelpInfoUri = $null
	,
		# Передавать полученный по конвейеру описатель дальше
		[switch]
		$PassThru
	)

	process {
		trap {
			break;
		};
		switch ( $PsCmdlet.ParameterSetName ) {
			'ModuleInfo' {
                if ( -not $HelpContentUri ) {
                    $HelpContentURI = "http://raw.github.com/IT-Service/$( $ModuleInfo.Name )/$( $ModuleInfo.Version )/help.cab";
                };
                if ( -not $HelpInfoUri ) {
                    $GitHubHelpInfoURI = "http://raw.github.com/IT-Service/$( $ModuleInfo.Name )/$( $ModuleInfo.Version )/$( $ModuleInfo.Name )_$( $ModuleInfo.GUID )_HelpInfo.xml";
                };
				$HelpInfoContent = Get-HelpInfo `
					-ModuleInfo $ModuleInfo `
				;
				$NewHelpInfoContent = New-HelpInfo `
					-ModuleInfo $ModuleInfo `
					-HelpContentUri $HelpContentUri `
				;

				$HelpInfoNS = [System.Xml.XmlNamespaceManager] ($NewHelpInfoContent.NameTable);
 				$HelpInfoNS.AddNamespace( 'hi', $HelpXMLNS.HelpInfo );

				$HelpContentURIEl = $HelpInfoContent.SelectSingleNode(
					'/hi:HelpInfo/hi:HelpContentURI'
					, $HelpInfoNS
				);
				if ( $HelpContentURIEl ) {
					$null = $HelpInfoContent.HelpInfo.RemoveChild( $HelpContentURIEl );
				};
				$null = $HelpInfoContent.HelpInfo.PrependChild(
					$HelpInfoContent.ImportNode(
						$NewHelpInfoContent.SelectSingleNode(
							'/hi:HelpInfo/hi:HelpContentURI'
							, $HelpInfoNS
						)
						, $true 
					)
				);
				$SupportedUICultures = $HelpInfoContent.SelectSingleNode(
					'/hi:HelpInfo/hi:SupportedUICultures'
					, $HelpInfoNS
				);
				$NewSupportedUICultures = $NewHelpInfoContent.HelpInfo.SupportedUICultures;
				$NewSupportedUICultures.UICulture `
				| % {
					$UICultureEl = $HelpInfoContent.SelectSingleNode(
						"/hi:HelpInfo/hi:SupportedUICultures/hi:UICulture[hi:UICultureName/text()='$( $_.UICultureName )']"
						, $HelpInfoNS
					);
					if ( $UICultureEl ) {
						$null = $SupportedUICultures.ReplaceChild(
							$HelpInfoContent.ImportNode( $_, $true )
							, $UICultureEl
						);
					} else {
						$null = $SupportedUICultures.AppendChild(
							$HelpInfoContent.ImportNode( $_, $true )
						);
					};
				};

				$HelpInfoPath = ( Join-Path `
					-Path ( Split-Path -Path ( $ModuleInfo.Path ) -Parent ) `
					-ChildPath "$( $ModuleInfo.Name )_$( $ModuleInfo.GUID )_HelpInfo.xml" `
				);
				$Writer = [System.Xml.XmlWriter]::Create(
					$HelpInfoPath `
					, ( New-Object `
						-TypeName System.Xml.XmlWriterSettings `
						-Property @{
							Indent = $true;
							OmitXmlDeclaration = $false;
							NamespaceHandling = [System.Xml.NamespaceHandling]::OmitDuplicates;
							NewLineOnAttributes = $false;
							CloseOutput = $true;
							IndentChars = "`t";
						} `
					) `
				);
				$HelpInfoContent.WriteTo( $Writer );
				$Writer.Close();

				if ( $UpdateManifest ) {
					$ModuleManifestPath = Join-Path `
						-Path ( $ModuleInfo.ModuleBase ) `
						-ChildPath "$( $ModuleInfo.Name ).psd1" `
					;
					if ( -not ( Test-Path -LiteralPath $ModuleManifestPath ) ) {
					    Write-Error `
						    -Message ( [String]::Format( $loc.ErrorModuleManifestPathMessage, $ModuleManifestPath ) ) `
						    -Category ResourceUnavailable `
						    -CategoryActivity ( $loc.ErrorModuleManifestPathActivity ) `
						    -CategoryReason ( $loc.ErrorModuleManifestPathReason ) `
						    -CategoryTargetName ( $FunctionInfo.Module.Name ) `
						    -TargetObject ( $FunctionInfo.Module ) `
						    -RecommendedAction ( $loc.ErrorModuleManifestPathRecommendedAction ) `
					    ;
						return;
					};
					( Get-Content `
						-LiteralPath $ModuleManifestPath `
						-ReadCount 0 `
					) `
					-join "`r`n" `
					-replace `
						"(?s)`r?`nHelpInfoUri\s*=\s*['`"].*?['`"]\s+|(?<!HelpInfoUri.*)(?=})" `
						, "`r`nHelpInfoUri = '$HelpInfoUri'`r`n`r`n" `
					| Set-Content `
						-LiteralPath $ModuleManifestPath `
						-Encoding 'UTF8' `
						-Force `
					;
				};
			}
		};
        
        if ( $PassThru ) { return $input };
	}
}

Export-ModuleMember `
	  Get-Readme `
	, Set-Readme `
	, Get-AboutModule `
	, Set-AboutModule `
	, New-HelpXML `
	, Get-HelpXML `
	, Set-HelpXML `
	, New-HelpInfo `
	, Get-HelpInfo `
	, Set-HelpInfo `
;
