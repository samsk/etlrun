<?xml version="1.0" encoding="utf-8"?>
<app:app xmlns:app="http://etl.dob.sk/app"  xmlns:etl="http://etl.dob.sk/etl">
<app:conf name="driver.http.agent">Mozilla/5.0 (Windows NT 6.1; WOW64; rv:5.0) Gecko/20100101 Firefox/5.0</app:conf>
<!-- application request -->
<app:req>
	<t:transform xmlns:t="http://etl.dob.sk/transform" stylesheet="xslt:embed://duckduckgo.xsl">
		<http:req http:method="get" xmlns:http="http://etl.dob.sk/http">
			<http:url>https://duckduckgo.com/</http:url>
			<http:param name="q" app:inject="q">duckduckgo</http:param>
		</http:req>
	</t:transform>
</app:req>

<!-- embedded xsl -->
<!-- digout zeroclick abstract from result page -->
<embed:embed id="duckduckgo.xsl" xmlns:embed="http://etl.dob.sk/embed">
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
				xmlns:xhtml="http://www.w3.org/1999/xhtml"
				xmlns:etl="http://etl.dob.sk/etl"
				exclude-result-prefixes="xhtml">
<xsl:output method="xml" indent="yes" encoding="utf-8"/>
<xsl:template match="/">
<result>
	<xsl:value-of select="//xhtml:div[@id = 'zero_click_abstract']"/>
</result>
</xsl:template>

</xsl:stylesheet>
</embed:embed>

</app:app>
