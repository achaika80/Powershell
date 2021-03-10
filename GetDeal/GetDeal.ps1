#Invoke-WebRequest -UseBasicParsing -Uri "https://www.bestbuy.com/site/hisense-65-class-h6510g-series-led-4k-uhd-smart-android-tv/6430857.p?skuId=6430857"

Function ConvertTo-NormalHTML {
    param([Parameter(Mandatory = $true, ValueFromPipeline = $true)]$HTML)

    $NormalHTML = New-Object -Com "HTMLFile"
    $NormalHTML.IHTMLDocument2_write($HTML.RawContent)
    return $NormalHTML
}

$Content = (Invoke-WebRequest -Method Get -Uri "https://www.bestbuy.com/site/hisense-65-class-h6510g-series-led-4k-uhd-smart-android-tv/6430857.p?skuId=6430857" -UseBasicParsing ).Content

$ParsedHTML = ConvertTo-NormalHTML -HTML $Content

$ParsedHTML